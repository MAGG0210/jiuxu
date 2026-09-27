import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ranks.dart';

const Color _blood = Color(0xFF8B0000);
const Color _bloodBright = Color(0xFFE53935);

/// 社区：小红书风格宫格流，展示所有人发布的公开笔记。
///
/// - **游客也能浏览**（无需登录）
/// - 发布 / 点赞 / 评论 需要登录
/// - 数据存在云端 `posts` / `post_likes` / `post_comments`
class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  List<Map<String, dynamic>> _posts = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  Map<String, int> _likeCounts = {};
  Map<String, int> _commentCounts = {};
  Set<String> _myLikes = {};
  RealtimeChannel? _channel;
  bool _loading = true;
  String? _error;

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
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // 1) 帖子（游客也能读）
      final rows = await Supabase.instance.client
          .from('posts')
          .select()
          .order('created_at', ascending: false)
          .limit(80);
      final posts = List<Map<String, dynamic>>.from(rows);
      final ids = posts.map((p) => p['id'].toString()).toList();

      // 2) 作者资料（头像 / 昵称 / 头衔）
      final authorIds = posts
          .map((p) => p['user_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final profiles = <String, Map<String, dynamic>>{};
      if (authorIds.isNotEmpty) {
        final pr = await Supabase.instance.client
            .from('profiles')
            .select('user_id, nickname, avatar_url, title, chat_days')
            .inFilter('user_id', authorIds);
        for (final r in pr) {
          profiles[r['user_id'].toString()] = Map<String, dynamic>.from(r);
        }
      }

      // 3) 点赞 / 评论计数
      final likeCounts = <String, int>{};
      final commentCounts = <String, int>{};
      final myLikes = <String>{};
      if (ids.isNotEmpty) {
        final likes = await Supabase.instance.client
            .from('post_likes')
            .select('post_id, user_id')
            .inFilter('post_id', ids);
        for (final l in likes) {
          final pid = l['post_id'].toString();
          likeCounts[pid] = (likeCounts[pid] ?? 0) + 1;
          if (_loggedIn && l['user_id'].toString() == _myId) myLikes.add(pid);
        }
        final comments = await Supabase.instance.client
            .from('post_comments')
            .select('post_id')
            .inFilter('post_id', ids);
        for (final c in comments) {
          final pid = c['post_id'].toString();
          commentCounts[pid] = (commentCounts[pid] ?? 0) + 1;
        }
      }

      if (!mounted) return;
      setState(() {
        _posts = posts;
        _profiles = profiles;
        _likeCounts = likeCounts;
        _commentCounts = commentCounts;
        _myLikes = myLikes;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '社区加载失败：$e';
      });
    }
  }

  void _subscribe() {
    _channel = Supabase.instance.client.channel('community-posts');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'posts',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  String _nameOf(Map<String, dynamic> post) {
    if (post['user_id'] == null) return '久序官方';
    final p = _profiles[post['user_id']?.toString()];
    final n = (p?['nickname'] ?? post['nickname'])?.toString();
    return (n == null || n.isEmpty) ? '无名者' : n;
  }

  String _titleOf(Map<String, dynamic> post) {
    if (post['user_id'] == null) return '官方';
    final p = _profiles[post['user_id']?.toString()];
    final t = p?['title']?.toString();
    if (t != null && t.isNotEmpty) return t;
    final days = int.tryParse('${p?['chat_days'] ?? ''}');
    return days == null ? '乞丐' : rankOf(days);
  }

  Future<void> _toggleLike(String postId) async {
    if (!_loggedIn) {
      _snack('登录后才能点赞');
      return;
    }
    final liked = _myLikes.contains(postId);
    // 乐观更新
    setState(() {
      final next = {..._myLikes};
      final counts = {..._likeCounts};
      if (liked) {
        next.remove(postId);
        counts[postId] = (counts[postId] ?? 1) - 1;
      } else {
        next.add(postId);
        counts[postId] = (counts[postId] ?? 0) + 1;
      }
      _myLikes = next;
      _likeCounts = counts;
    });
    try {
      if (liked) {
        await Supabase.instance.client
            .from('post_likes')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', _myId!);
      } else {
        await Supabase.instance.client
            .from('post_likes')
            .insert({'post_id': postId, 'user_id': _myId});
      }
    } catch (e) {
      _snack('操作失败：$e');
      await _load();
    }
  }

  Future<void> _publish() async {
    if (!_loggedIn) {
      _snack('登录后才能发布到社区');
      return;
    }
    final ctrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(sheetCtx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('发布到社区',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('会以你的昵称 + 王室头衔公开显示',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(sheetCtx)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55))),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 6,
                minLines: 3,
                decoration: const InputDecoration(
                  hintText: '分享点什么…（会同步到云端，所有人可见）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    final text = ctrl.text.trim();
                    if (text.isEmpty) return;
                    try {
                      await Supabase.instance.client.from('posts').insert({
                        'user_id': _myId,
                        'content': text,
                      });
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      await _load();
                      _snack('已发布');
                    } catch (e) {
                      _snack('发布失败：$e（云端 posts 表可能还没建）');
                    }
                  },
                  child: const Text('发布',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 打开详情（评论 + 点赞）
  Future<void> _openDetail(Map<String, dynamic> post) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailPage(
          post: post,
          authorName: _nameOf(post),
          authorTitle: _titleOf(post),
          avatarUrl: _profiles[post['user_id']?.toString()]?['avatar_url']
              ?.toString(),
          liked: _myLikes.contains(post['id'].toString()),
          likeCount: _likeCounts[post['id'].toString()] ?? 0,
          onToggleLike: () => _toggleLike(post['id'].toString()),
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'community-fab',
        onPressed: _publish,
        backgroundColor: _bloodBright,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('发布',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_on_rounded,
                size: 56,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('社区还没有内容',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            const Text('登录后点右下角 + 发布第一条',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.8,
        ),
        itemCount: _posts.length,
        itemBuilder: (context, i) => _buildCard(_posts[i]),
      ),
    );
  }

  /// 小红书风格卡片
  Widget _buildCard(Map<String, dynamic> post) {
    final pid = post['id'].toString();
    final content = (post['content'] ?? '').toString();
    final scheme = Theme.of(context).colorScheme;
    final liked = _myLikes.contains(pid);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openDetail(post),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 作者行
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Row(
                children: [
                  _avatar(post['user_id']?.toString(), 26),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_nameOf(post),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      gradient:
                          const LinearGradient(colors: [_blood, _bloodBright]),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(_titleOf(post),
                        style: const TextStyle(
                            fontSize: 9.5, color: Colors.white)),
                  ),
                ],
              ),
            ),
            // 正文
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(content,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: scheme.onSurface.withValues(alpha: 0.85))),
              ),
            ),
            // 底部互动
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 10, 6),
              child: Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _toggleLike(pid),
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: liked ? _bloodBright : Colors.grey,
                    ),
                  ),
                  Text('${_likeCounts[pid] ?? 0}',
                      style: const TextStyle(fontSize: 11.5)),
                  const SizedBox(width: 4),
                  const Icon(Icons.mode_comment_outlined,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('${_commentCounts[pid] ?? 0}',
                      style: const TextStyle(fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String? uid, double size) {
    // 官方号：金色皇冠徽记
    if (uid == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFFDFBF5),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFD4AF37)),
        ),
        child: Icon(Icons.workspace_premium,
            size: size * 0.62, color: const Color(0xFFD4AF37)),
      );
    }
    final url = _profiles[uid]?['avatar_url']?.toString();
    final name = _nameOf({'user_id': uid});
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_blood, _bloodBright]),
        shape: BoxShape.circle,
      ),
      child: Text(name.characters.first,
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.45,
              fontWeight: FontWeight.w600)),
    );
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback),
    );
  }
}

/// 帖子详情：完整内容 + 点赞 + 评论区（评论需登录）
class PostDetailPage extends StatefulWidget {
  final Map<String, dynamic> post;
  final String authorName;
  final String authorTitle;
  final String? avatarUrl;
  final bool liked;
  final int likeCount;
  final VoidCallback onToggleLike;

  const PostDetailPage({
    super.key,
    required this.post,
    required this.authorName,
    required this.authorTitle,
    required this.avatarUrl,
    required this.liked,
    required this.likeCount,
    required this.onToggleLike,
  });

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final _commentCtrl = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  Map<String, Map<String, dynamic>> _commentProfiles = {};
  bool _loading = true;
  bool _liked = false;
  int _likes = 0;
  bool _changed = false;

  bool get _loggedIn => Supabase.instance.client.auth.currentSession != null;
  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _liked = widget.liked;
    _likes = widget.likeCount;
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final rows = await Supabase.instance.client
          .from('post_comments')
          .select()
          .eq('post_id', widget.post['id'])
          .order('created_at', ascending: true);
      final list = List<Map<String, dynamic>>.from(rows);
      final ids = list
          .map((c) => c['user_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final profiles = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final pr = await Supabase.instance.client
            .from('profiles')
            .select('user_id, nickname, avatar_url, title, chat_days')
            .inFilter('user_id', ids);
        for (final r in pr) {
          profiles[r['user_id'].toString()] = Map<String, dynamic>.from(r);
        }
      }
      if (!mounted) return;
      setState(() {
        _comments = list;
        _commentProfiles = profiles;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendComment() async {
    if (!_loggedIn) {
      _snack('登录后才能评论');
      return;
    }
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await Supabase.instance.client.from('post_comments').insert({
        'post_id': widget.post['id'],
        'user_id': _myId,
        'content': text,
      });
      _commentCtrl.clear();
      _changed = true;
      await _loadComments();
    } catch (e) {
      _snack('评论失败：$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toggleLike() {
    if (!_loggedIn) {
      _snack('登录后才能点赞');
      return;
    }
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
    });
    widget.onToggleLike();
    _changed = true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('帖子')),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  // 作者
                  Row(
                    children: [
                      _commentAvatar(widget.avatarUrl, widget.authorName, 38),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.authorName,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 1.5),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [_blood, _bloodBright]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(widget.authorTitle,
                                  style: const TextStyle(
                                      fontSize: 10.5, color: Colors.white)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleLike,
                        icon: Icon(
                          _liked ? Icons.favorite : Icons.favorite_border,
                          color: _liked ? _bloodBright : Colors.grey,
                        ),
                      ),
                      Text('$_likes', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 正文
                  Text((widget.post['content'] ?? '').toString(),
                      style: const TextStyle(fontSize: 15, height: 1.6)),
                  const SizedBox(height: 20),
                  Divider(color: Colors.black.withValues(alpha: 0.08)),
                  const SizedBox(height: 8),
                  Text('评论 ${_comments.length}',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text('还没有评论',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurface
                                    .withValues(alpha: 0.5))),
                      ),
                    )
                  else
                    ..._comments.map(_buildComment),
                ],
              ),
            ),
            _buildCommentInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildComment(Map<String, dynamic> c) {
    final uid = c['user_id']?.toString();
    final p = _commentProfiles[uid];
    final name = p?['nickname']?.toString() ?? '无名者';
    final title = p?['title']?.toString() ??
        rankOf(int.tryParse('${p?['chat_days'] ?? 0}') ?? 0);
    final url = p?['avatar_url']?.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _commentAvatar(url, name, 30),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [_blood, _bloodBright]),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 9.5, color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text((c['content'] ?? '').toString(),
                    style: const TextStyle(fontSize: 13.5, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentAvatar(String? url, String name, double size) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_blood, _bloodBright]),
        shape: BoxShape.circle,
      ),
      child: Text(name.isEmpty ? '?' : name.characters.first,
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.45,
              fontWeight: FontWeight.w600)),
    );
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback),
    );
  }

  Widget _buildCommentInput() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
            top: BorderSide(color: dark ? Colors.white12 : Colors.black12)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendComment(),
                  decoration: InputDecoration(
                    hintText: _loggedIn ? '说点什么…' : '登录后可评论',
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
              IconButton(
                onPressed: _sendComment,
                icon: const Icon(Icons.send_rounded, color: _bloodBright),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
