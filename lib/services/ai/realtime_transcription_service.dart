import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../../utils/ui_formatters.dart';

/// 本地实时转写服务 - 基于 sherpa-onnx Online Paraformer
class RealtimeTranscriptionService {
  static final RealtimeTranscriptionService _instance =
      RealtimeTranscriptionService._internal();
  static RealtimeTranscriptionService get instance => _instance;

  RealtimeTranscriptionService._internal();

  static const _sampleRate = 16000;
  static const _streamBufferSize = 3200;
  static const _decodeTick = Duration(milliseconds: 120);
  static const _maxPreviewChars = 50;

  final AudioRecorder _recorder = AudioRecorder();
  final _transcriptionController = StreamController<String>.broadcast();
  final _isListeningController = StreamController<bool>.broadcast();
  final _partialTranscriptionController = StreamController<String>.broadcast();

  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  String? _modelDir;
  String? _recordingPath;

  StreamSubscription<Uint8List>? _audioStreamSubscription;
  Timer? _decodeTimer;
  final Stopwatch _recordingStopwatch = Stopwatch();

  final List<Float32List> _recordingAudioChunks = <Float32List>[];
  int _recordingSampleCount = 0;

  String _currentTranscription = '';
  String _partialTranscription = '';
  bool _isListening = false;
  bool _isPreparing = false;

  Stream<String> get transcriptionStream => _transcriptionController.stream;
  Stream<bool> get isListeningStream => _isListeningController.stream;
  Stream<String> get partialTranscriptionStream =>
      _partialTranscriptionController.stream;

  bool get isListening => _isListening;
  bool get isReady => _recognizer != null;
  String get currentTranscription => _currentTranscription;
  String get partialTranscription => _partialTranscription;
  String get accumulatedTranscription => _currentTranscription;
  String? get recordingPath => _recordingPath;
  Duration get recordingDuration => _recordingStopwatch.elapsed;

  void configure({String? url, String? key, String? model}) {
    // 本地在线识别不需要远端配置，保留接口兼容现有调用方。
  }

  Future<bool> initialize() async {
    if (_recognizer != null) {
      return true;
    }
    if (_isPreparing) {
      while (_isPreparing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _recognizer != null;
    }

    _isPreparing = true;
    try {
      sherpa_onnx.initBindings();
      final supportDir = await getApplicationSupportDirectory();
      final modelDir = Directory('${supportDir.path}/paraformer');
      await modelDir.create(recursive: true);

      final encoderPath = await _copyAssetIfNeeded(
        'assets/paraformer/encoder.int8.onnx',
        '${modelDir.path}/encoder.int8.onnx',
      );
      final decoderPath = await _copyAssetIfNeeded(
        'assets/paraformer/decoder.int8.onnx',
        '${modelDir.path}/decoder.int8.onnx',
      );
      final tokensPath = await _copyAssetIfNeeded(
        'assets/paraformer/tokens.txt',
        '${modelDir.path}/tokens.txt',
      );

      final config = sherpa_onnx.OnlineRecognizerConfig(
        feat: const sherpa_onnx.FeatureConfig(
          sampleRate: _sampleRate,
          featureDim: 80,
        ),
        model: sherpa_onnx.OnlineModelConfig(
          paraformer: sherpa_onnx.OnlineParaformerModelConfig(
            encoder: encoderPath,
            decoder: decoderPath,
          ),
          tokens: tokensPath,
          numThreads: 2,
          provider: 'cpu',
          debug: false,
        ),
        decodingMethod: 'greedy_search',
        enableEndpoint: false,
      );

      _recognizer = sherpa_onnx.OnlineRecognizer(config);
      _modelDir = modelDir.path;
      return true;
    } catch (_) {
      return false;
    } finally {
      _isPreparing = false;
    }
  }

  Future<void> startListening() async {
    if (_isListening) {
      return;
    }

    final isInitialized = await initialize();
    if (!isInitialized) {
      throw Exception('本地实时识别模型初始化失败');
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('录音权限被拒绝，请检查权限设置');
    }

    final tempDir = await getTemporaryDirectory();
    _recordingPath =
        '${tempDir.path}/shiguanlast-${DateTime.now().millisecondsSinceEpoch}.wav';

    clearTranscription();
    _recordingAudioChunks.clear();
    _recordingSampleCount = 0;
    _stream?.free();
    _stream = _recognizer?.createStream();

    _recordingStopwatch
      ..reset()
      ..start();
    _isListening = true;
    _isListeningController.add(true);

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        streamBufferSize: _streamBufferSize,
        autoGain: true,
        noiseSuppress: true,
      ),
    );

    _audioStreamSubscription = audioStream.listen(_handleAudioChunk);
    _decodeTimer?.cancel();
    _decodeTimer = Timer.periodic(_decodeTick, (_) => _decodeAvailable());
  }

  Future<void> stopListening() async {
    if (!_isListening) {
      return;
    }

    _recordingStopwatch.stop();
    _isListening = false;
    _isListeningController.add(false);

    _decodeTimer?.cancel();
    _decodeTimer = null;

    await _recorder.stop();
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;

    final stream = _stream;
    final recognizer = _recognizer;
    if (stream != null && recognizer != null) {
      stream.inputFinished();
      _decodeAvailable(forceFlush: true);
    }

    final path = _recordingPath;
    if (path != null && _recordingSampleCount > 0) {
      sherpa_onnx.writeWave(
        filename: path,
        samples: _snapshotRecordingSamples(),
        sampleRate: _sampleRate,
      );
    }
  }

  void clearTranscription() {
    _currentTranscription = '';
    _partialTranscription = '';
    _recordingStopwatch
      ..stop()
      ..reset();
    _transcriptionController.add('');
    _partialTranscriptionController.add('');
  }

  Future<String> decodeBundledSample() async {
    final isInitialized = await initialize();
    if (!isInitialized || _modelDir == null) {
      throw Exception('本地实时识别模型初始化失败');
    }

    final wavPath = await _copyAssetIfNeeded(
      'assets/sensevoice/zh.wav',
      '$_modelDir/zh.wav',
    );
    final audio = sherpa_onnx.readWave(wavPath);
    final recognizer = _recognizer;
    if (recognizer == null) {
      throw StateError('Recognizer has not been initialized.');
    }

    final stream = recognizer.createStream();
    stream.acceptWaveform(samples: audio.samples, sampleRate: audio.sampleRate);
    stream.inputFinished();
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    final result = recognizer.getResult(stream);
    stream.free();

    final text = _cleanRecognizedText(result.text);
    return text.isEmpty ? '[未识别出文本]' : text;
  }

  void _handleAudioChunk(Uint8List data) {
    final samples = _pcm16BytesToFloat32(data);
    if (samples.isEmpty) {
      return;
    }

    _recordingAudioChunks.add(samples);
    _recordingSampleCount += samples.length;
    _stream?.acceptWaveform(samples: samples, sampleRate: _sampleRate);
    _decodeAvailable();
  }

  void _decodeAvailable({bool forceFlush = false}) {
    final recognizer = _recognizer;
    final stream = _stream;
    if (recognizer == null || stream == null) {
      return;
    }

    var didDecode = false;
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
      didDecode = true;
    }

    if (!didDecode && !forceFlush) {
      return;
    }

    final result = recognizer.getResult(stream);
    final text = _cleanRecognizedText(result.text);
    _currentTranscription = text;
    _partialTranscription = _lastChars(text, _maxPreviewChars);
    _transcriptionController.add(_currentTranscription);
    _partialTranscriptionController.add(_partialTranscription);
  }

  Float32List _snapshotRecordingSamples() {
    final samples = Float32List(_recordingSampleCount);
    var offset = 0;
    for (final chunk in _recordingAudioChunks) {
      samples.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return samples;
  }

  Float32List _pcm16BytesToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final byteData = ByteData.sublistView(bytes, 0, sampleCount * 2);
    final samples = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  String _cleanRecognizedText(String text) {
    final trimmed = text.trim();
    return trimmed == '[未识别出文本]' ? '' : compactVoiceText(trimmed);
  }

  String _lastChars(String text, int count) {
    final normalized = text.trim();
    if (normalized.length <= count) {
      return normalized;
    }
    return normalized.substring(normalized.length - count);
  }

  Future<String> _copyAssetIfNeeded(String assetPath, String targetPath) async {
    final file = File(targetPath);
    if (await file.exists()) {
      return file.path;
    }

    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }

  void dispose() {
    _decodeTimer?.cancel();
    _audioStreamSubscription?.cancel();
    _recordingStopwatch.stop();
    _stream?.free();
    _recognizer?.free();
    _recorder.dispose();
    _transcriptionController.close();
    _isListeningController.close();
    _partialTranscriptionController.close();
  }
}
