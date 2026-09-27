import 'dart:async';
import 'package:flutter/material.dart';
import 'main.dart';

/// 开场动画：星空图缓推放大 + 淡入，约 3 秒后淡入主界面。
///
/// 同时会等启动数据加载完成（[appReady]，最多 8 秒）才跳转 ——
/// 否则 Supabase 还没初始化就进主界面会直接空白（黑屏）。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _zoom;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000));

    // 图片：淡入 + 从 1.12 缓推到 1.0（缓慢推进的镜头感）
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
    );
    _zoom = Tween<double>(begin: 1.12, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );

    _run();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    await Future.wait<void>([
      // 动画播完
      _ctrl.forward().orCancel.then((_) {}).catchError((_) {}),
      // 启动数据加载完（超时兜底，绝不永久停在开场页）
      appReady.future
          .timeout(const Duration(seconds: 8), onTimeout: () {})
          .catchError((_) {}),
    ]);
    _goHome();
  }

  /// 动画结束 → 淡入主界面
  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => const RootPage(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06101F),
      body: SizedBox.expand(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _zoom,
            child: Image.asset(
              'assets/splash.jpg',
              fit: BoxFit.cover,
              // 载图期间保持底色，避免出现白色闪屏
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: Color(0xFF06101F),
                child: Center(
                  child: Text(
                    '久序',
                    style: TextStyle(
                      color: Color(0xFFFFD54F),
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
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

