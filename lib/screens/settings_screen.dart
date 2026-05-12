import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/ai/ai_service_config.dart';
import '../services/ai/realtime_transcription_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_responsive.dart';
import '../widgets/glass_card.dart';
import '../widgets/ui_asset_icon.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;

  bool _smartCorrection = true;
  bool _isSaving = false;
  bool _isRecordingLocked = false;
  StreamSubscription<bool>? _recordingSub;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    final transcriptionService = RealtimeTranscriptionService.instance;
    _isRecordingLocked = transcriptionService.isListening;
    _recordingSub = transcriptionService.isListeningStream.listen((
      isRecording,
    ) {
      if (!mounted) {
        return;
      }
      setState(() => _isRecordingLocked = isRecording);
    });
  }

  void _loadConfig() {
    _apiUrlController = TextEditingController(
      text: AIServiceConfig.getCurrentApiUrl(),
    );
    _apiKeyController = TextEditingController(
      text: AIServiceConfig.getCurrentApiKey() ?? '',
    );
    _modelController = TextEditingController(
      text: AIServiceConfig.getCurrentModel(),
    );
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _recordingSub?.cancel();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (_isRecordingLocked) {
      _showMessage('正在录音，暂不能修改 AI 配置', Colors.orange[400]!);
      return;
    }

    final apiKey = _apiKeyController.text.trim();
    final apiUrl = _apiUrlController.text.trim();
    final modelName = _modelController.text.trim();

    if (apiKey.isEmpty) {
      _showMessage('请输入 API Key', Colors.orange[400]!);
      return;
    }
    if (apiUrl.isEmpty) {
      _showMessage('请输入 API 地址', Colors.orange[400]!);
      return;
    }
    if (modelName.isEmpty) {
      _showMessage('请输入模型名称', Colors.orange[400]!);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await AIServiceConfig.initDeepseek(apiKey, url: apiUrl, model: modelName);
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      _showMessage('配置已保存', Colors.green[400]!);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      _showMessage('保存失败: $e', Colors.orange[400]!);
    }
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.8, -0.9),
                radius: 0.8,
                colors: [Color(0x8CC2E9FB), Colors.transparent],
              ),
            ),
            child: Container(color: const Color(0xF0EEF8F4)),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    14,
                    14,
                    widget.embedded
                        ? AppResponsive.bottomNavReserve(context) + 10
                        : 96,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SecLabel(
                        icon: Icons.auto_awesome,
                        label: 'DeepSeek 配置',
                        color: Color(0xFF5ECFA0),
                      ),
                      const SizedBox(height: 10),
                      GlassCard2(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isRecordingLocked) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF5D9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0x66F0B84A),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.lock_outline,
                                      size: 15,
                                      color: Color(0xFF9A6A16),
                                    ),
                                    SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        '正在录音，AI 配置已锁定',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF9A6A16),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            const Text(
                              '当前仅保留 DeepSeek，默认建议使用 deepseek-v4-pro。',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSub,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _CfgField(
                              controller: _apiUrlController,
                              hint: 'API 地址',
                              enabled: !_isRecordingLocked,
                            ),
                            const SizedBox(height: 8),
                            _CfgField(
                              controller: _apiKeyController,
                              hint: 'API Key',
                              obscure: true,
                              enabled: !_isRecordingLocked,
                            ),
                            const SizedBox(height: 8),
                            _CfgField(
                              controller: _modelController,
                              hint: '模型名称',
                              enabled: !_isRecordingLocked,
                            ),
                          ],
                        ),
                      ),
                      const _Divider(),
                      const _SecLabel(
                        icon: Icons.mic,
                        label: '本地语音识别',
                        color: Color(0xFF6BAED6),
                      ),
                      const SizedBox(height: 10),
                      GlassCard2(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _ReadonlyInfoRow(
                              label: '识别方案',
                              value: 'sherpa-onnx Online Paraformer 本地实时识别',
                            ),
                            const SizedBox(height: 8),
                            _ReadonlyInfoRow(
                              label: 'Voice 模型',
                              value: AIServiceConfig.getAsrModel(),
                            ),
                            const SizedBox(height: 8),
                            const _ReadonlyInfoRow(
                              label: '识别模式',
                              value: '仅本地模型，不使用在线 ASR',
                            ),
                            const SizedBox(height: 8),
                            const _ReadonlyInfoRow(
                              label: '说明',
                              value: '录音时本机实时识别，停止后把全文交给 DeepSeek 做笔记整理。',
                            ),
                          ],
                        ),
                      ),
                      const _Divider(),
                      const _SecLabel(
                        icon: Icons.settings,
                        label: '通用选项',
                        color: AppColors.textSub,
                      ),
                      const SizedBox(height: 10),
                      GlassCard2(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 12,
                        ),
                        child: _Toggle(
                          label: '智能纠错',
                          value: _smartCorrection,
                          onChanged: (v) =>
                              setState(() => _smartCorrection = v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  14,
                  0,
                  14,
                  widget.embedded
                      ? AppResponsive.bottomNavReserve(context) + 4
                      : 24,
                ),
                child: GestureDetector(
                  onTap: (_isSaving || _isRecordingLocked) ? null : _saveConfig,
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: (_isSaving || _isRecordingLocked)
                            ? [Colors.grey[400]!, Colors.grey[300]!]
                            : const [Color(0xFFA8EDDA), Color(0xFF6BAED6)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x4750C8AA),
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_isRecordingLocked && !_isSaving) ...[
                          const UiAssetIcon('保存.png', size: 18),
                          const SizedBox(width: 7),
                        ],
                        Text(
                          _isRecordingLocked
                              ? '录音中，配置已锁定'
                              : (_isSaving ? '保存中...' : '完成并保存'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E4A40),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: content,
    );
  }

  Widget _buildHeader() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          decoration: const BoxDecoration(
            color: Color(0x70FFFFFF),
            border: Border(bottom: BorderSide(color: Color(0x33FFFFFF))),
          ),
          child: Row(
            children: [
              if (!widget.embedded) ...[
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.arrow_back,
                    size: 30,
                    color: AppColors.textSub,
                  ),
                ),
                const SizedBox(width: 9),
              ],
              const Text(
                '配置中心',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecLabel extends StatelessWidget {
  const _SecLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _CfgField extends StatelessWidget {
  const _CfgField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.62,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0x8CFFFFFF),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xCCFFFFFF), width: 1.5),
        ),
        child: TextField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 11.5,
              color: AppColors.textSub.withValues(alpha: 0.6),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),
            border: InputBorder.none,
            isDense: true,
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, this.value = false, this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textDark),
          ),
          Container(
            width: 36,
            height: 20,
            decoration: BoxDecoration(
              gradient: value
                  ? const LinearGradient(
                      colors: [Color(0xFFA8EDDA), Color(0xFF6BAED6)],
                    )
                  : null,
              color: value ? null : Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 14),
      color: const Color(0x1E96B4D2),
    );
  }
}

class _ReadonlyInfoRow extends StatelessWidget {
  const _ReadonlyInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textSub,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textDark,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
