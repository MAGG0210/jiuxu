import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'profile_store.dart';
import 'ranks.dart';

const Color _blood = Color(0xFF8B0000);
const Color _bloodBright = Color(0xFFE53935);

/// 聊天室：云端消息 + 实时推送。
///
/// 消息卡片显示 **头像 / 昵称 / 王室头衔**；头衔实时从 `profiles` 表读取，
/// 用户在别处晋升后这里会跟着变（订阅了 profiles 与 messages 两张表）。
/// 游客与未登录用户只能看，不能发言（没有云端身份）。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  Map<String, Map<String, dynamic>> _profiles = {}; // user_id -> 最新资料
  RealtimeChannel? _msgChannel;
  RealtimeChannel? _profileChannel;
  bool _loading = true;
  String? _error;
  bool _sending = false;

  bool get _loggedIn => Supabase.instance.client.auth.currentSession != null;
  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _msgChannel?.unsubscribe();
    _profileChannel?.unsubscribe();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_loggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('messages')
          .select()
          .order('created_at', ascending: false)
          .limit(120);
      final list = List<Map<String, dynamic>>.from(rows).reversed.toList();
      await _refreshProfiles(list);
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
        _error = null;
      });
      _jumpToBottom();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载失败：$e';
        });
      }
    }
  }

  /// 拉取消息里出现过的用户的最新资料（昵称 / 头像 / 头衔）
  Future<void> _refreshProfiles(List<Map<String, dynamic>> msgs) async {
    final ids = msgs
        .map((m) => m['user_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    final rows = await Supabase.instance.client
        .from('profiles')
        .select('user_id, nickname, avatar_url, title, chat_days')
        .inFilter('user_id', ids);
    final map = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      map[r['user_id'].toString()] = Map<String, dynamic>.from(r);
    }
    if (mounted) {
      // 合并而不是整体替换：只把查到的那几个用户更新进来。
      // （旧写法直接 _profiles = map，发一条消息就只查自己，
      //   其他人的头像/昵称/头衔会全部丢失并退回旧快照 —— 表现为"头像变成字"）
      setState(() => _profiles = {..._profiles, ...map});
    }
  }

  void _subscribe() {
    if (!_loggedIn) return;
    final client = Supabase.instance.client;

    _msgChannel = client.channel('chat-messages');
    _msgChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (!mounted) return;
            _appendMessage(row);
            await _refreshProfiles([row]);
          },
        )
        .subscribe();

    // 头衔 / 昵称 / 头像变更 → 聊天室立即刷新显示
    _profileChannel = client.channel('chat-profiles');
    _profileChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (_) => _refreshProfiles(_messages),
        )
        .subscribe();
  }

  /// 追加消息（按 id 去重：本地乐观插入与 Realtime 回推不会重复显示）
  void _appendMessage(Map<String, dynamic> msg) {
    final id = msg['id']?.toString();
    if (id != null && _messages.any((m) => m['id']?.toString() == id)) return;
    setState(() => _messages = [..._messages, msg]);
    _jumpToBottom();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    if (!_loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登录后才能发言，游客模式只能浏览')));
      return;
    }
    setState(() => _sending = true);
    try {
      // .select().single() 让服务端把刚插入的行回传：拿到后**立刻本地渲染**，
      // 不再只依赖 Realtime 回推（推送没到或没配好时，自己发的消息会看不见）
      final row = await Supabase.instance.client
          .from('messages')
          .insert({
            'user_id': _myId,
            'nickname': ProfileStore.nickname,
            'avatar_url': ProfileStore.avatarUrl,
            'title': ProfileStore.title,
            'content': text,
          })
          .select()
          .single();
      _ctrl.clear();
      if (mounted) {
        final msg = Map<String, dynamic>.from(row);
        _appendMessage(msg);
        await _refreshProfiles([msg]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _displayName(Map<String, dynamic> m) {
    final uid = m['user_id']?.toString() ?? '';
    // 自己：永远以本机最新资料为准（改昵称/头像后历史消息也同步）
    if (uid == _myId && ProfileStore.nickname.isNotEmpty) {
      return ProfileStore.nickname;
    }
    final p = _profiles[uid];
    final n = p?['nickname']?.toString() ?? m['nickname']?.toString();
    return (n == null || n.isEmpty) ? '无名者' : n;
  }

  /// 头衔实时优先（来自 profiles），回退到消息快照
  String _displayTitle(Map<String, dynamic> m) {
    final uid = m['user_id']?.toString() ?? '';
    final p = _profiles[uid];
    final t = p?['title']?.toString();
    if (t != null && t.isNotEmpty) return t;
    final days = int.tryParse('${p?['chat_days'] ?? ''}');
    if (days != null) return rankOf(days);
    final snap = m['title']?.toString();
    return (snap == null || snap.isEmpty) ? '乞丐' : snap;
  }

  String? _avatarUrl(Map<String, dynamic> m) {
    final uid = m['user_id']?.toString() ?? '';
    // 自己：永远以本机最新头像为准（换过头像后历史消息也显示新头像）
    if (uid == _myId) {
      final mine = ProfileStore.avatarUrl;
      if (mine != null && mine.isNotEmpty) return mine;
    }
    final p = _profiles[uid];
    final u = p?['avatar_url']?.toString() ?? m['avatar_url']?.toString();
    return (u == null || u.isEmpty) ? null : u;
  }

  String _formatTime(String? iso) {
    final dt = DateTime.tryParse(iso ?? '')?.toLocal();
    if (dt == null) return '';
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return hm;
    }
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hm';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedIn) return _buildNeedLogin();
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: _buildList()),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildNeedLogin() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: AppColors.gradientSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.forum_outlined,
                  size: 42, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text('聊天室需要登录',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(
              '聊天室是云端公共空间，需要账号才能发言。\n游客模式可以先浏览本机笔记与待办。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.7,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 56,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('还没有人说话，来打个招呼吧',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55))),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      itemCount: _messages.length,
      itemBuilder: (context, i) => _buildBubble(_messages[i]),
    );
  }

  Widget _buildBubble(Map<String, dynamic> m) {
    final mine = m['user_id']?.toString() == _myId;
    final url = _avatarUrl(m);
    final name = _displayName(m);
    final title = _displayTitle(m);

    final avatar = _Avatar(url: url, name: name, size: 38);
    final header = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.75))),
        const SizedBox(width: 6),
        // 王室头衔标签
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_blood, _bloodBright]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 6),
        Text(_formatTime(m['created_at']?.toString()),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: mine
            ? _blood.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: mine ? _blood.withValues(alpha: 0.4) : Colors.black12,
        ),
      ),
      child: Text((m['content'] ?? '').toString(),
          style: const TextStyle(fontSize: 14.5, height: 1.35)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: mine
            ? [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [header, const SizedBox(height: 4), bubble],
                ),
                const SizedBox(width: 8),
                avatar,
              ]
            : [
                avatar,
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [header, const SizedBox(height: 4), bubble],
                ),
              ],
      ),
    );
  }

  Widget _buildInput() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: dark ? Colors.white12 : Colors.black12)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: '说点什么…',
                    isDense: true,
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: _bloodBright),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆形头像：优先网络图，失败或没有则显示昵称首字
class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  const _Avatar({required this.url, required this.name, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_blood, _bloodBright]),
        shape: BoxShape.circle,
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600),
      ),
    );
    if (url == null) return fallback;
    return ClipOval(
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (c, child, p) => p == null ? child : fallback,
      ),
    );
  }
}
