import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'note_service.dart';
import 'note_edit_page.dart';
import 'app_theme.dart';

/// 笔记列表页：Realtime 订阅任何端的变化，实时刷新。
class NotesPage extends StatefulWidget {
  const NotesPage({super.key});
  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;
  String? _error;
  RealtimeChannel? _channel;
  Timer? _debounce;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _activeTag;

  /// 视图模式：宫格（默认）/ 列表
  bool _gridView = true;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      var notes = await NoteService.instance.fetchNotes();
      // 首次打开：自动生成一条默认欢迎笔记（只做一次）
      if (notes.isEmpty && await _seedWelcomeNoteIfNeeded()) {
        notes = await NoteService.instance.fetchNotes();
      }
      if (mounted) {
        setState(() {
          _notes = notes;
          _loading = false;
          _error = null;
          // 若当前筛选的标签已不存在，清除筛选
          if (_activeTag != null &&
              !_allTags.contains(_activeTag)) {
            _activeTag = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载失败: $e';
        });
      }
    }
  }

  static const String _welcomeFlagKey = 'welcome_note_created_v1';

  /// 首次使用写入欢迎笔记；已写过则返回 false
  Future<bool> _seedWelcomeNoteIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_welcomeFlagKey) == true) return false;
    await prefs.setBool(_welcomeFlagKey, true);
    try {
      await NoteService.instance.createNote(
        title: '欢迎来到久序',
        content: '这里是你自己的小宇宙 👑\n\n'
            '· 笔记：右下角 + 新建，支持 Markdown、标签、置顶、回收站\n'
            '· 待办：给每件事设一个提醒时间，到点会弹窗提醒你\n'
            '· 打卡：内置 3 条习惯，坚持打卡可以看到连续天数\n'
            '· 聊天室 / 社区：登录后可以与人交流、分享见闻\n\n'
            '按自己的节奏来就好 —— 停下来吧，你本该成为王。\n',
        tags: ['开始'],
        pinned: true,
      );
      return true;
    } catch (_) {
      return false; // 创建失败不影响使用
    }
  }

  void _subscribe() {
    final uid = NoteService.instance.userId;
    _channel = NoteService.instance.subscribeNotes(
      forUserId: uid,
      onChanged: () {
        // 防抖：多条变更合并为一次刷新
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), _load);
      },
    );
  }

  // ---------- 文本处理 ----------
  /// 将 Markdown 内容简化为纯文本摘要
  String _stripMarkdown(String s) {
    return s
        .replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '')
        .replaceAll(RegExp(r'\[(.*?)\]\(.*?\)'), r'$1')
        .replaceAll(RegExp(r'#{1,6}\s*'), '')
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'[*_~`>]'), '')
        .trim();
  }

  // ---------- 搜索 / 筛选 ----------
  List<String> get _allTags {
    final set = <String>{};
    for (final n in _notes) {
      final tags = (n['tags'] as List?)?.map((e) => e.toString()) ?? const [];
      set.addAll(tags);
    }
    return set.toList()..sort();
  }

  List<Map<String, dynamic>> get _filteredNotes {
    final q = _search.trim().toLowerCase();
    return _notes.where((n) {
      if (_activeTag != null) {
        final tags =
            (n['tags'] as List?)?.map((e) => e.toString()) ?? const <String>[];
        if (!tags.contains(_activeTag)) return false;
      }
      if (q.isNotEmpty) {
        final title = (n['title'] ?? '').toString().toLowerCase();
        final content = (n['content'] ?? '').toString().toLowerCase();
        if (!title.contains(q) && !content.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  // ---------- 复制 / 导出 ----------
  Future<void> _copyNote(Map<String, dynamic> note) async {
    final text = _noteToText(note);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制到剪贴板')));
    }
  }

  Future<void> _exportNote(Map<String, dynamic> note) async {
    final title = (note['title'] ?? '久序').toString();
    final text = _noteToText(note);
    await Share.share(text, subject: title);
  }

  String _noteToText(Map<String, dynamic> note) {
    final title = (note['title'] ?? '').toString().trim();
    final content = (note['content'] ?? '').toString();
    final tags = (note['tags'] as List?)?.map((e) => e.toString()) ?? const [];
    final tagStr =
        tags.isEmpty ? '' : '\n\n标签：${tags.map((t) => '#$t').join(' ')}';
    if (title.isEmpty) return content;
    return '$title\n\n$content$tagStr';
  }

  // ---------- 时间格式化 ----------
  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 页面标题由主壳顶部栏居中显示（左上角头像 / 右上角王室图标之间）
      floatingActionButton: FloatingActionButton(
        // 唯一 heroTag：IndexedStack 里同时存在多个 FAB，共用默认 tag 会让
        // 任何页面跳转在 Hero 过渡阶段抛异常（表现为"点了没反应"）
        heroTag: 'notes-fab',
        onPressed: () async {
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const NoteEditPage()),
          );
          if (changed == true) _load();
        },
        // 渐变背景 FAB
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.gradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
      body: Column(
        children: [
          // 游客模式提示条：明确告知不会同步到云端
          if (NoteService.isGuest)
            Container(
              width: double.infinity,
              color: Colors.orange.withValues(alpha: 0.12),
              padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
              child: Row(
                children: [
                  Icon(Icons.cloud_off,
                      size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '游客模式 · 数据只存本机，未开启云备份',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                  TextButton(
                    onPressed: () => NoteService.instance.exitGuestMode(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('去登录', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          // 搜索框 + 宫格/列表视图切换
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 6, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: '搜索笔记…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              },
                            ),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                IconButton(
                  tooltip: _gridView ? '切换为列表视图' : '切换为宫格视图',
                  onPressed: () => setState(() => _gridView = !_gridView),
                  icon: Icon(_gridView
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded),
                ),
              ],
            ),
          ),
          // 标签筛选栏
          if (_allTags.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('全部'),
                      visualDensity: VisualDensity.compact,
                      selected: _activeTag == null,
                      onSelected: (_) => setState(() => _activeTag = null),
                    ),
                  ),
                  ..._allTags.map((t) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('#$t'),
                          visualDensity: VisualDensity.compact,
                          selected: _activeTag == t,
                          onSelected: (_) =>
                              setState(() => _activeTag = _activeTag == t ? null : t),
                        ),
                      )),
                ],
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final notes = _filteredNotes;
    if (notes.isEmpty) {
      return Center(
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
              child: Icon(Icons.notes,
                  size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              _notes.isEmpty
                  ? '还没有笔记，点右下角 + 新建'
                  : '没有匹配的笔记',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _gridView
          ? GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              itemCount: notes.length,
              itemBuilder: (context, i) => _buildNoteGridCard(notes[i]),
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: notes.length,
              itemBuilder: (context, i) => _buildNoteCard(notes[i]),
            ),
    );
  }

  /// 宫格卡片（默认视图）：标题 + 摘要 + 标签 + 时间
  Widget _buildNoteGridCard(Map<String, dynamic> note) {
    final title = (note['title'] ?? '无标题').toString();
    final content = _stripMarkdown((note['content'] ?? '').toString());
    final updated = _formatTime(note['updated_at']?.toString());
    final pinned = note['pinned'] == true;
    final tags = (note['tags'] as List?)?.map((e) => e.toString()) ?? const [];
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => NoteEditPage(note: note)),
        );
        if (changed == true) _load();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: AppColors.gradientSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (pinned) ...[
                  Icon(Icons.push_pin, size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                content.isEmpty ? '（空笔记）' : content,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: scheme.onSurface.withValues(alpha: 0.65)),
              ),
            ),
            if (tags.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: tags
                    .take(3)
                    .map((t) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('#$t',
                              style: TextStyle(
                                  fontSize: 10, color: scheme.primary)),
                        ))
                    .toList(),
              ),
            const SizedBox(height: 4),
            Text(updated,
                style:
                    TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteCard(Map<String, dynamic> note) {
    final title = (note['title'] ?? '无标题').toString();
    final content = (note['content'] ?? '').toString();
    final updated = _formatTime(note['updated_at']?.toString());
    final pinned = note['pinned'] == true;
    final tags = (note['tags'] as List?)?.map((e) => e.toString()) ?? const [];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: pinned
            ? Icon(Icons.push_pin, color: Colors.orange.shade600, size: 20)
            : null,
        title: Text(title,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (content.isNotEmpty)
              Text(_stripMarkdown(content),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(
                  spacing: 6,
                  children: tags
                      .map((t) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('#$t',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary)),
                          ))
                      .toList(),
                ),
              ),
            if (updated.isNotEmpty)
              Text(updated,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (v) {
            if (v == 'copy') _copyNote(note);
            if (v == 'export') _exportNote(note);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'copy', child: Text('复制')),
            PopupMenuItem(value: 'export', child: Text('导出/分享')),
          ],
        ),
        onTap: () async {
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => NoteEditPage(note: note)),
          );
          if (changed == true) _load();
        },
      ),
    );
  }
}


