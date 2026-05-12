import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:gif_view/gif_view.dart';

// GifStatus is part of gif_view package

String _gifAssetPath(String name) {
  if (name.startsWith('ui/')) {
    return name;
  }
  return 'ui/$name';
}

/// 普通GIF：一直循环播放
class AppGif extends StatefulWidget {
  final String name;
  final double size;
  final BoxFit fit;

  const AppGif(
    this.name, {
    super.key,
    this.size = 28,
    this.fit = BoxFit.contain,
  });

  @override
  State<AppGif> createState() => _AppGifState();
}

class _AppGifState extends State<AppGif> {
  late GifController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = GifController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Icon(
            Icons.broken_image,
            size: widget.size * 0.5,
            color: Colors.grey[400],
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GifView.asset(
        _gifAssetPath(widget.name),
        controller: _controller,
        width: widget.size,
        height: widget.size,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _hasError = true);
            }
          });
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Icon(
              Icons.broken_image,
              size: widget.size * 0.5,
              color: Colors.grey[400],
            ),
          );
        },
      ),
    );
  }
}

/// 点击触发GIF：平时停在第一帧，点击播放一遍后精确停在最后一帧/第一帧
class TapGif extends StatefulWidget {
  final String name;
  final double size;
  final BoxFit fit;
  final VoidCallback? onTap;

  /// 播放完毕后的延迟回调（用于先播动画再跳转）
  final VoidCallback? onFinished;

  /// 是否允许点击触发（有些场景是由外层手势控制动画播放，避免双触发）
  final bool enableTap;

  const TapGif(
    this.name, {
    super.key,
    this.size = 28,
    this.fit = BoxFit.contain,
    this.onTap,
    this.onFinished,
    this.enableTap = true,
  });

  @override
  State<TapGif> createState() => TapGifState();
}

class TapGifState extends State<TapGif> {
  late final GifController _ctrl;
  bool _playing = false;
  Timer? _finishTimer;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _ctrl = GifController();
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onGifFinish() {
    if (!mounted) return;
    setState(() => _playing = false);
    try {
      _ctrl.seek(0);
      _ctrl.stop();
    } catch (e) {
      // 忽略错误
    }
    widget.onFinished?.call();
  }

  /// 自动轮播使用：只播放GIF，不触发 onTap/onFinished 回调。
  void playAuto() {
    if (!mounted || _hasError) return;
    setState(() => _playing = true);
    try {
      _ctrl.seek(0);
      _ctrl.play();
    } catch (e) {
      // 忽略错误
    }
  }

  /// 切换轮播图标使用：强制停止并回到第0帧。
  void stop() {
    if (!mounted) return;
    _finishTimer?.cancel();
    setState(() => _playing = false);
    try {
      _ctrl.seek(0);
      _ctrl.stop();
    } catch (e) {
      // 忽略错误
    }
  }

  /// 点击交互使用：播放GIF，并在结束时触发 onFinished。
  /// 即使动画正在播放，也会触发 onTap 回调
  void trigger({Duration? playFor}) {
    // 始终触发 onTap 回调，即使动画正在播放
    widget.onTap?.call();

    if (_playing || _hasError) return;
    setState(() => _playing = true);
    try {
      _ctrl.seek(0);
      _ctrl.play();
    } catch (e) {
      // 忽略错误
    }

    // 假设GIF播放约1秒后结束，用于触发回调
    _finishTimer?.cancel();
    _finishTimer = Timer(playFor ?? const Duration(milliseconds: 800), () {
      if (mounted) _onGifFinish();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Icon(
          Icons.broken_image,
          size: widget.size * 0.5,
          color: Colors.grey[400],
        ),
      );
    }

    final gif = SizedBox(
      width: widget.size,
      height: widget.size,
      child: _SafeGifView(
        name: _gifAssetPath(widget.name),
        controller: _ctrl,
        size: widget.size,
        fit: widget.fit,
        onError: () {
          if (mounted) {
            setState(() => _hasError = true);
          }
        },
      ),
    );

    if (!widget.enableTap) return gif;
    return GestureDetector(onTap: () => trigger(), child: gif);
  }
}

/// 自动随机脉冲GIF：
/// 每隔`every`秒，按概率触发播放一次；播放完后回到第一帧静止。
/// 不依赖点击（适合“看得到动画但不影响点击跳转”的场景）。
class RandomPulseGif extends StatefulWidget {
  final String name;
  final double size;
  final BoxFit fit;

  /// 基础周期（默认10秒）
  final Duration every;

  /// 首次触发的随机偏移（用于让多个图标不会同时动）
  final Duration initialJitter;

  /// 每个周期触发播放的概率（默认0.5）
  final double probability;

  const RandomPulseGif({
    super.key,
    required this.name,
    this.size = 28,
    this.fit = BoxFit.contain,
    this.every = const Duration(seconds: 10),
    this.initialJitter = const Duration(seconds: 10),
    this.probability = 0.5,
  });

  @override
  State<RandomPulseGif> createState() => _RandomPulseGifState();
}

class _RandomPulseGifState extends State<RandomPulseGif> {
  late final GifController _ctrl;
  late final Random _rnd;
  Timer? _timer;
  Timer? _playTimer;
  bool _playing = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _rnd = Random();
    _ctrl = GifController();

    final jitterMs = widget.initialJitter.inMilliseconds;
    final firstDelayMs = jitterMs <= 0 ? 0 : _rnd.nextInt(jitterMs + 1);
    _timer = Timer(Duration(milliseconds: firstDelayMs), _tickOnce);
  }

  void _onFinish() {
    if (!mounted) return;
    setState(() => _playing = false);
    try {
      _ctrl.seek(0);
      _ctrl.stop();
    } catch (e) {
      // 忽略错误
    }
  }

  void _tickOnce() {
    if (!mounted) return;
    // 触发一次后，再按周期走
    _timer?.cancel();
    _timer = Timer.periodic(widget.every, (_) => _maybePlay());
    _maybePlay();
  }

  void _maybePlay() {
    if (!mounted || _hasError) return;
    if (_playing) return;
    if (_rnd.nextDouble() > widget.probability) return;

    setState(() => _playing = true);
    try {
      _ctrl.seek(0);
      _ctrl.play();
    } catch (e) {
      // 忽略错误
    }

    // 假设GIF播放约1秒
    _playTimer?.cancel();
    _playTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _onFinish();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _playTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Icon(
          Icons.broken_image,
          size: widget.size * 0.5,
          color: Colors.grey[400],
        ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: _SafeGifView(
        name: _gifAssetPath(widget.name),
        controller: _ctrl,
        size: widget.size,
        fit: widget.fit,
        onError: () {
          if (mounted) {
            setState(() => _hasError = true);
          }
        },
      ),
    );
  }
}

/// 安全GIF视图 - 捕获渲染错误
class _SafeGifView extends StatefulWidget {
  final String name;
  final GifController controller;
  final double size;
  final BoxFit fit;
  final IconData errorIcon;
  final VoidCallback onError;

  const _SafeGifView({
    required this.name,
    required this.controller,
    required this.size,
    required this.fit,
    this.errorIcon = Icons.broken_image,
    required this.onError,
  });

  @override
  State<_SafeGifView> createState() => _SafeGifViewState();
}

class _SafeGifViewState extends State<_SafeGifView> {
  bool _hasFailed = false;

  @override
  Widget build(BuildContext context) {
    if (_hasFailed) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Icon(
            widget.errorIcon,
            size: widget.size * 0.5,
            color: Colors.grey[400],
          ),
        ),
      );
    }

    return GifView.asset(
      widget.name,
      controller: widget.controller,
      width: widget.size,
      height: widget.size,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_hasFailed) {
            setState(() => _hasFailed = true);
            widget.onError();
          }
        });
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: Icon(
              widget.errorIcon,
              size: widget.size * 0.5,
              color: Colors.grey[400],
            ),
          ),
        );
      },
    );
  }
}

/// 工作时播放的GIF - 只有当 isWorking 为 true 时才播放动画，否则停在第一帧
/// 适合用于录音状态、加载状态等场景
class WorkingGif extends StatefulWidget {
  final String name;
  final double size;
  final BoxFit fit;
  final bool isWorking;

  const WorkingGif(
    this.name, {
    super.key,
    this.size = 28,
    this.fit = BoxFit.contain,
    required this.isWorking,
  });

  @override
  State<WorkingGif> createState() => _WorkingGifState();
}

class _WorkingGifState extends State<WorkingGif> {
  late final GifController _ctrl;
  bool _lastWorking = false;
  Timer? _loopTimer;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _ctrl = GifController();
    _lastWorking = widget.isWorking;
  }

  bool get _canPlay => !_hasError;

  void _startLoopTimer() {
    _loopTimer?.cancel();
    // 假设GIF播放约1秒后循环
    _loopTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && widget.isWorking && !_hasError) {
        try {
          _ctrl.seek(0);
          _ctrl.play();
          _startLoopTimer();
        } catch (e) {
          // 忽略 GIF 控制错误
        }
      }
    });
  }

  @override
  void didUpdateWidget(WorkingGif oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isWorking != _lastWorking) {
      _lastWorking = widget.isWorking;
      if (widget.isWorking && _canPlay) {
        try {
          _ctrl.seek(0);
          _ctrl.play();
          _startLoopTimer();
        } catch (e) {
          // 忽略 GIF 控制错误
        }
      } else {
        _loopTimer?.cancel();
        try {
          _ctrl.seek(0);
          _ctrl.stop();
        } catch (e) {
          // 忽略 GIF 控制错误
        }
      }
    }
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: _hasError
              ? Icon(
                  Icons.mic,
                  size: widget.size * 0.5,
                  color: Colors.grey[400],
                )
              : const SizedBox.shrink(),
        ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: _SafeGifView(
        name: _gifAssetPath(widget.name),
        controller: _ctrl,
        size: widget.size,
        fit: widget.fit,
        errorIcon: Icons.mic,
        onError: () {
          if (mounted) {
            setState(() => _hasError = true);
          }
        },
      ),
    );
  }
}

class AppImg extends StatelessWidget {
  final String name;
  final double? width;
  final double? height;
  final BoxFit fit;

  const AppImg(
    this.name, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset('ui/$name', width: width, height: height, fit: fit);
  }
}
