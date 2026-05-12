import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'data/app_repository.dart';
import 'data/shared_prefs_app_repository.dart';
import 'screens/home_screen.dart';
import 'services/ai/ai_service_config.dart';
import 'services/foreground_service_handler.dart';

const _preloadGifAssets = [
  'ui/挨揍.gif',
  'ui/擦汗.gif',
  'ui/喝水与吐出来.gif',
  'ui/瞌睡.gif',
  'ui/鹿野的Q版形象-眼睛变色.gif',
  'ui/鹿野q版-拍照.gif',
  'ui/罗小黑的Q版形象-点头.gif',
  'ui/罗小黑的Q版形象-看手机炸毛.gif',
  'ui/罗小黑的Q版形象-趴着地上摆烂.gif',
  'ui/罗小黑的Q版形象-思考.gif',
  'ui/罗小黑的Q版形象-探头.gif',
  'ui/罗小黑的Q版形象-偷听-可用于语音识别开启按钮.gif',
  'ui/罗小黑的Q版形象-羡慕.gif',
  'ui/罗小黑的Q版形象剪刀手.gif',
  'ui/罗小黑竖大拇指.gif',
  'ui/摸头.gif',
  'ui/哪种合可乐打嗝.gif',
  'ui/发送键-点击触发动效.gif',
  'ui/跳跃1.gif',
  'ui/跳跃2.gif',
  'ui/跳跃3.gif',
  'ui/跳跃4.gif',
  'ui/无限的Q版形象-用杯子喝水.gif',
  'ui/小黑猫（罗小黑）-地上打滚.gif',
  'ui/小黑猫（罗小黑）-玩3个黑球-可用于加载.gif',
  'ui/小黑猫（罗小黑）-原地跑步.gif',
  'ui/用力拍桌子.gif',
  'ui/Q版形象-打开扇子（扇子是有妥字）可用于保存.gif',
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 加载保存的 AI 配置
  await AIServiceConfig.loadConfig();
  await ForegroundServiceHandler.init();
  final repository = await SharedPrefsAppRepository.create();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(ShiguangApp(repository: repository));
}

class ShiguangApp extends StatelessWidget {
  const ShiguangApp({super.key, required this.repository});

  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    return Provider<AppRepository>.value(
      value: repository,
      child: MaterialApp(
        title: '拾光 AI 笔记',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'Noto Sans SC',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFA8EDDA),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            },
          ),
        ),
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          final textScale = mediaQuery.textScaler
              .scale(1)
              .clamp(0.9, 1.15)
              .toDouble();
          return MediaQuery(
            data: mediaQuery.copyWith(textScaler: TextScaler.linear(textScale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const _StartupGate(),
      ),
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmUpAssets();
    });
  }

  Future<void> _warmUpAssets() async {
    final minDisplay = Future<void>.delayed(const Duration(milliseconds: 1500));
    final preload = Future.wait<void>(
      _preloadGifAssets.map((asset) async {
        try {
          await precacheImage(AssetImage(asset), context);
        } catch (_) {
          // 单个动图预加载失败不阻塞启动，页面自身会显示失败兜底。
        }
      }),
    );
    await Future.wait([minDisplay, preload]);
    if (!mounted) {
      return;
    }
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _ready ? const HomeScreen() : const _LaunchScreen(),
    );
  }
}

class _LaunchScreen extends StatefulWidget {
  const _LaunchScreen();

  @override
  State<_LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<_LaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..forward();
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(curve);
    _scale = Tween<double>(begin: 0.9, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(curve);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2FAF7),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.65, -0.78),
            radius: 0.9,
            colors: [Color(0xB8A8EDDA), Color(0x00A8EDDA)],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: ScaleTransition(
                scale: _scale,
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.zcoolXiaoWei(
                      fontSize: 48,
                      height: 1,
                      color: const Color(0xFF1E2D4A),
                      shadows: const [
                        Shadow(
                          color: Color(0x663DC6B5),
                          blurRadius: 28,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    children: [
                      const TextSpan(text: '拾光'),
                      TextSpan(
                        text: ' AI',
                        style: GoogleFonts.zcoolXiaoWei(
                          fontSize: 48,
                          foreground: Paint()
                            ..shader = const LinearGradient(
                              colors: [Color(0xFF38BDA5), Color(0xFF8B5CF6)],
                            ).createShader(const Rect.fromLTWH(0, 0, 120, 60)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
