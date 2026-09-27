import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'note_service.dart';
import 'auth_page.dart';
import 'home_shell.dart';
import 'splash_page.dart';
import 'habit_store.dart';
import 'profile_store.dart';
import 'theme_store.dart';
import 'todo_store.dart';
import 'app_theme.dart';

/// App 初始化完成的信号：SplashPage 会等它（最多 8 秒）再进主界面。
final Completer<void> appReady = Completer<void>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 关键：先把 UI 起起来，再异步加载数据。
  // 旧写法是在 runApp 之前 await 一串网络初始化（Supabase + 云端数据），
  // 任何一步慢/超时/失败都会让窗口一直空白 —— 表现就是"莫名其妙黑屏"。
  //
  // 只在 release/profile 下替换错误显示：debug 下保留 Flutter 默认行为，
  // 且 flutter_test 会断言 ErrorWidget.builder 未被修改（跑集成测试就是 debug）。
  if (kReleaseMode || kProfileMode) {
    ErrorWidget.builder = (details) => const _FriendlyError();
  }
  runApp(const NotesApp());

  await _bootstrap();
}

/// 启动数据加载：每步独立容错 + 限时，任何一步失败都不影响进入 App
Future<void> _bootstrap() async {
  try {
    await NoteService.init().timeout(const Duration(seconds: 12));
    await NoteService.loadGuestState();
  } catch (e) {
    debugPrint('Supabase 初始化失败（降级为可用状态）：$e');
  }

  for (final step in <Future<void> Function()>[
    TodoStore.load,
    HabitStore.load,
    ProfileStore.load,
    ThemeStore.load,
  ]) {
    try {
      await step().timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('数据加载失败（跳过）：$e');
    }
  }

  if (!appReady.isCompleted) appReady.complete();
}

/// release 模式下 widget build 抛异常会渲染成一片空白（看起来就是黑屏），
/// 这里兜底成可读提示，至少不会漆黑一片让人以为卡死。
class _FriendlyError extends StatelessWidget {
  const _FriendlyError();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF1A0606),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '这一页出了点小问题\n返回上一页再进来试试',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFFFD54F), fontSize: 15, height: 1.6),
            ),
          ),
        ),
      ),
    );
  }
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.notifier,
      builder: (context, mode, _) =>
          ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: ProfileStore.settings,
        builder: (context, settings, __) {
          final scale = (settings['fontScale'] as num?)?.toDouble() ?? 1.0;
          return MaterialApp(
            title: '久序',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            // 全局字体缩放（设置 → 通用 → 字体大小）
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const SplashPage(),
          );
        },
      ),
    );
  }
}

/// 三路分流：
/// - 游客模式 -> 主界面（数据只在本机，无云备份/签到）
/// - 已登录   -> 主界面（云端同步）
/// - 都没有   -> 登录页
///
/// 同时监听 Supabase 认证状态流与游客开关，任一变化都会立即切换。
class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: NoteService.guestNotifier,
      builder: (context, guest, _) {
        if (guest) return const HomeShell();
        // Supabase 还没初始化完：先给登录页，初始化完成后这里会随
        // 认证状态流自动切换，避免直接访问 Supabase.instance 抛异常
        if (!NoteService.ready) return const AuthPage();
        return StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            final session = snapshot.data?.session;
            if (session != null) {
              return const HomeShell();
            }
            return const AuthPage();
          },
        );
      },
    );
  }
}
