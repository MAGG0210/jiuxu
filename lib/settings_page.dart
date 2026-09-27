import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'note_service.dart';
import 'profile_store.dart';
import 'todo_store.dart';
import 'theme_store.dart';

/// 设置中心：通用 / 通知 / 隐私 / 账号 / 关于
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool get _loggedIn => Supabase.instance.client.auth.currentSession != null;

  Future<void> _set(String key, Object? value) async {
    await ProfileStore.setSetting(key, value);
    if (mounted) setState(() {});
  }

  /// 导出本机数据（笔记 + 待办）为文本分享出去
  Future<void> _exportData() async {
    try {
      final buf = StringBuffer()
        ..writeln('久序 · 数据导出')
        ..writeln('导出时间：${DateTime.now()}')
        ..writeln('账号：${_loggedIn ? NoteService.instance.email : '游客（本地）'}')
        ..writeln('');

      final notes = await NoteService.instance.fetchNotes();
      buf.writeln('=== 笔记（${notes.length}）===');
      for (final n in notes) {
        buf.writeln('· ${n['title'] ?? '无标题'}');
        final c = (n['content'] ?? '').toString().trim();
        if (c.isNotEmpty) buf.writeln('  $c');
        buf.writeln('');
      }

      final todos = TodoStore.todos;
      buf.writeln('=== 待办（${todos.length}）===');
      for (final t in todos) {
        final done = t['done'] == true ? '[x]' : '[ ]';
        final remind = t['remind_at'] == null
            ? ''
            : '  ⏰ ${DateTime.tryParse(t['remind_at'].toString())?.toLocal() ?? ''}';
        buf.writeln('$done ${t['title']}$remind');
      }

      await Share.share(buf.toString(), subject: '久序数据导出');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    }
  }

  Future<void> _clearLocalCache() async {
    final ok = await _confirm(
      title: '清除本地缓存？',
      content: '会清掉本机的游客笔记与待办清单，云端数据不受影响。此操作不可撤销。',
      confirmText: '清除',
      danger: true,
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('guest_notes_v1');
    await prefs.remove('todos_v1');
    await TodoStore.load();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('本地缓存已清除')));
    }
  }

  Future<void> _deleteAccount() async {
    if (!_loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('游客模式没有云端账号可注销')));
      return;
    }
    final ok = await _confirm(
      title: '注销账号？',
      content: '将清空云端所有笔记、打卡记录、待办、聊天消息与个人资料，且无法恢复。',
      confirmText: '确认注销',
      danger: true,
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc('delete_my_account_data');
      await NoteService.instance.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('云端数据已清空，已退出登录')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('注销失败：$e（云端函数可能还没执行 supabase_social.sql）')));
      }
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String content,
    String confirmText = '确定',
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: Colors.red.shade400)
                : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('隐私协议'),
        content: const SingleChildScrollView(
          child: Text(
            '1. 账号信息：邮箱仅用于登录与身份识别。\n'
            '2. 笔记/待办/打卡/聊天数据：登录状态下存储在云端（Supabase），用于多端同步；'
            '游客模式只存在本机，不会上传。\n'
            '3. 头像：登录用户上传的头像存储在云端公开桶中，聊天室与资料页可见。\n'
            '4. 打卡可见范围、通知开关等都可在本页设置。\n'
            '5. 你可以随时导出数据或注销账号；注销会清空云端全部数据。\n'
            '6. 我们不会把数据出售给第三方。',
            style: TextStyle(height: 1.7, fontSize: 13.5),
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(c), child: const Text('知道了')),
        ],
      ),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: '久序',
      applicationVersion: '1.0.0 (build 1)',
      applicationIcon: const Icon(Icons.workspace_premium, size: 40),
      children: const [
        Text('自律打卡 + 云笔记 + 王室头衔 + 聊天室。\n'
            '停下来吧，你本该成为王。'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ProfileStore.settings.value;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ---------- 通用 ----------
          _sectionTitle('通用设置'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('深色模式'),
            subtitle: const Text('跟随系统时以系统设置为准'),
            value: Theme.of(context).brightness == Brightness.dark,
            onChanged: (v) => ThemeStore.set(v ? ThemeMode.dark : ThemeMode.light),
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('字体大小'),
            subtitle: Text(_fontLabel(
                (s['fontScale'] as num?)?.toDouble() ?? 1.0)),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                min: 0.85,
                max: 1.3,
                divisions: 3,
                value: (s['fontScale'] as num?)?.toDouble() ?? 1.0,
                label: _fontLabel(
                    (s['fontScale'] as num?)?.toDouble() ?? 1.0),
                onChanged: (v) => _set('fontScale', v),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('提示音'),
            value: s['sound'] == true,
            onChanged: (v) => _set('sound', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('震动'),
            value: s['vibrate'] == true,
            onChanged: (v) => _set('vibrate', v),
          ),

          // ---------- 通知 ----------
          _sectionTitle('通知设置'),
          SwitchListTile(
            secondary: const Icon(Icons.event_available),
            title: const Text('习惯打卡提醒'),
            value: s['notifyCheckin'] == true,
            onChanged: (v) => _set('notifyCheckin', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.alarm),
            title: const Text('任务到期提醒'),
            value: s['notifyTodo'] == true,
            onChanged: (v) => _set('notifyTodo', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.nightlight_outlined),
            title: const Text('每日复盘提醒'),
            subtitle: Text('提醒时间 ${s['dailyReviewAt'] ?? '21:00'}'),
            value: s['notifyReview'] == true,
            onChanged: (v) => _set('notifyReview', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.forum_outlined),
            title: const Text('聊天室消息推送'),
            value: s['notifyChat'] == true,
            onChanged: (v) => _set('notifyChat', v),
          ),

          // ---------- 隐私 ----------
          _sectionTitle('隐私设置'),
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('打卡记录可见范围'),
            subtitle: Text(_visibilityLabel(
                s['checkinVisibility']?.toString() ?? 'public')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final cur = s['checkinVisibility']?.toString() ?? 'public';
              final picked = await showDialog<String>(
                context: context,
                builder: (c) => SimpleDialog(
                  title: const Text('谁能看到我的打卡记录'),
                  children: [
                    for (final o in const [
                      ('public', '所有人可见'),
                      ('friends', '仅好友可见'),
                      ('private', '仅自己可见'),
                    ])
                      ListTile(
                        leading: Icon(
                          o.$1 == cur
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: o.$1 == cur
                              ? Theme.of(c).colorScheme.primary
                              : null,
                        ),
                        title: Text(o.$2),
                        onTap: () => Navigator.pop(c, o.$1),
                      ),
                  ],
                ),
              );
              if (picked != null) await _set('checkinVisibility', picked);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_outlined),
            title: const Text('云端同步'),
            subtitle: const Text('关闭后只在本机保存，不再上传'),
            value: s['cloudSync'] == true,
            onChanged: (v) => _set('cloudSync', v),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('数据导出'),
            subtitle: const Text('笔记 + 待办导出为文本'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _exportData,
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清除本地缓存'),
            subtitle: const Text('清理本机游客笔记与待办'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _clearLocalCache,
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隐私协议'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showPrivacyPolicy,
          ),

          // ---------- 账号 ----------
          _sectionTitle('账号管理'),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(_loggedIn ? '退出登录' : '退出游客模式'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final nav = Navigator.of(context);
              await NoteService.instance.signOut();
              nav.pop();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined,
                color: Colors.red.shade400),
            title: Text('注销账号',
                style: TextStyle(color: Colors.red.shade400)),
            subtitle: const Text('清空云端全部数据，不可恢复'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _deleteAccount,
          ),

          // ---------- 关于 ----------
          _sectionTitle('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本号'),
            subtitle: const Text('1.0.0 (build 1)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showAbout,
          ),
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('意见反馈'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Share.share('久序 App 反馈：\n\n（写下你的建议）',
                  subject: '久序 · 意见反馈');
            },
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('停下来吧，你本该成为王',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.35))),
          ),
        ],
      ),
    );
  }

  static String _fontLabel(double v) {
    if (v <= 0.87) return '小';
    if (v <= 1.02) return '标准';
    if (v <= 1.16) return '大';
    return '特大';
  }

  static String _visibilityLabel(String v) => switch (v) {
        'friends' => '仅好友可见',
        'private' => '仅自己可见',
        _ => '所有人可见',
      };

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(t,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.9))),
      );
}


