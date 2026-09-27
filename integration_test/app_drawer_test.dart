import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notes_app/home_shell.dart';
import 'package:notes_app/main.dart' as app;

/// 真实端到端验证（Windows 桌面真启动 App 并点击）。
///
/// 两个注意点：
/// 1. 不用 `pumpAndSettle`：App 内有定时器与实时连接，永远不会真正 settle；
/// 2. 不用固定等待：启动要联网初始化 Supabase + 拉云端数据，改为轮询等待关键元素。
Future<void> waitForAny(
  WidgetTester tester,
  List<Finder> finders, {
  int seconds = 30,
}) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    for (final f in finders) {
      if (f.evaluate().isNotEmpty) return;
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('左上角开侧边栏 / 关闭 / 右上角开王室页 / 切 tab', (tester) async {
    app.main();
    await tester.pump();

    final loginText = find.text('登录');
    final avatar = find.byType(UserAvatar);
    final guestEntry = find.textContaining('游客登录');

    // 1) 等 App 初始化完成（停在登录页，或直接进了主界面）
    await waitForAny(tester, [guestEntry, loginText, avatar], seconds: 40);

    // 2) 若在登录页 → 以游客身份进入
    if (guestEntry.evaluate().isNotEmpty) {
      await tester.tap(guestEntry.first);
      await waitForAny(tester, [loginText, avatar], seconds: 25);
    }

    final inHome =
        loginText.evaluate().isNotEmpty || avatar.evaluate().isNotEmpty;
    expect(inHome, isTrue, reason: '应已进入主界面（左上角有「登录」或头像）');

    // ★ 3) 点左上角 → 侧边栏必须打开
    if (loginText.evaluate().isNotEmpty) {
      await tester.tap(loginText.first);
    } else {
      await tester.tap(avatar.first);
    }
    await waitForAny(tester, [find.text('修改头像')], seconds: 10);
    expect(find.text('修改头像'), findsOneWidget, reason: '★ 侧边栏没有打开');
    expect(find.text('番茄钟'), findsOneWidget, reason: '侧边栏应有番茄钟入口');
    expect(find.text('设置'), findsWidgets);

    // ★ 4) 点侧边栏外空白 → 关闭
    await tester.tapAt(const Offset(680, 420));
    await waitForAny(tester, [find.text('我的习惯')], seconds: 4);
    expect(find.text('修改头像'), findsNothing, reason: '点空白应关闭侧边栏');

    // ★ 5) 右上角王室入口（此前会因 FAB Hero tag 冲突而抛异常）
    await tester.tap(find.byIcon(Icons.workspace_premium).first);
    await waitForAny(tester, [find.text('王室谱系')], seconds: 12);

    if (find.text('王室谱系').evaluate().isEmpty) {
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .toList();
      // ignore: avoid_print
      print('DIAG 点击王室图标后页面文本: $texts');
    }
    expect(find.text('王室谱系'), findsOneWidget, reason: '王室页应打开');

    // RoyalPage 用页内自定义返回按钮（没有 AppBar 的 BackButton）
    await tester.tap(find.byIcon(Icons.arrow_back));
    await waitForAny(tester, [find.byIcon(Icons.event_available_rounded)],
        seconds: 8);

    // ★ 6) 底部 tab 切换（用图标定位，避免与页面标题文字重名）
    await tester.tap(find.byIcon(Icons.event_available_rounded));
    await waitForAny(tester, [find.text('我的习惯')], seconds: 10);
    expect(find.text('我的习惯'), findsOneWidget, reason: '打卡页应显示习惯清单');
  });
}
