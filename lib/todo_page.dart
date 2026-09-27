import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'todo_store.dart';

const Color _blood = Color(0xFF8B0000);
const Color _bloodBright = Color(0xFFE53935);
const Color _gold = Color(0xFFFFD54F);

/// 待办清单：本机存储 + 到点提醒。
///
/// 提醒为应用内弹窗（每 20 秒扫描一次），支持「10 分钟后再提醒」。
class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) => _checkDue());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkDue());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 扫描到点的提醒并弹窗
  Future<void> _checkDue() async {
    if (!mounted) return;
    final due = TodoStore.dueNow();
    if (due.isEmpty) return;
    for (final t in due) {
      await TodoStore.markNotified(t['id'] as String);
    }
    if (!mounted) return;
    _showReminder(due.first);
  }

  void _showReminder(Map<String, dynamic> todo) {
    final id = todo['id'] as String;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF140606),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _blood.withValues(alpha: 0.6)),
        ),
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: _bloodBright, size: 22),
            SizedBox(width: 8),
            Text('时间到了',
                style: TextStyle(
                    color: _gold, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          (todo['title'] ?? '').toString(),
          style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              await TodoStore.update(
                  id: id,
                  remindAt: DateTime.now().add(const Duration(minutes: 10)));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('好，10 分钟后再提醒你')));
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: const Text('10 分钟后再提醒'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _blood, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(c);
              await TodoStore.toggle(id);
            },
            child: const Text('标记完成'),
          ),
        ],
      ),
    );
  }

  /// 日期 + 时间两步选择
  Future<DateTime?> _pickDateTime(BuildContext ctx, DateTime? initial) async {
    final now = DateTime.now();
    final base = initial ?? now.add(const Duration(minutes: 30));
    final d = await showDatePicker(
      context: ctx,
      initialDate: base,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      helpText: '选择提醒日期',
    );
    if (d == null || !ctx.mounted) return null;
    final t = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay.fromDateTime(base),
      helpText: '选择提醒时间',
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  /// 新建 / 编辑（底部弹出）
  Future<void> _openEditor({Map<String, dynamic>? todo}) async {
    final isNew = todo == null;
    final titleCtrl =
        TextEditingController(text: todo?['title']?.toString() ?? '');
    DateTime? remindAt = todo?['remind_at'] == null
        ? null
        : DateTime.tryParse(todo!['remind_at'].toString());

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(sheetCtx).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(isNew ? '新建待办' : '编辑待办',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  autofocus: isNew,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '要做什么',
                    prefixIcon: Icon(Icons.edit_note),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // 提醒时间行
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await _pickDateTime(sheetCtx, remindAt);
                    if (picked != null) setSheet(() => remindAt = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(sheetCtx).dividerColor),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          remindAt == null ? Icons.alarm_add : Icons.alarm_on,
                          size: 20,
                          color: remindAt == null
                              ? Colors.grey
                              : _bloodBright,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            remindAt == null
                                ? '设置提醒时间（可选）'
                                : _formatRemind(remindAt!),
                            style: TextStyle(
                              fontSize: 14,
                              color: remindAt == null
                                  ? Colors.grey
                                  : null,
                              fontWeight: remindAt == null
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (remindAt != null)
                          GestureDetector(
                            onTap: () => setSheet(() => remindAt = null),
                            child: const Icon(Icons.close,
                                size: 18, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                GradientButton(
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) {
                      ScaffoldMessenger.of(sheetCtx).showSnackBar(
                          const SnackBar(content: Text('先写点内容吧')));
                      return;
                    }
                    if (isNew) {
                      await TodoStore.add(title: title, remindAt: remindAt);
                    } else {
                      await TodoStore.update(
                        id: todo['id'] as String,
                        title: title,
                        remindAt: remindAt,
                        clearRemind: remindAt == null,
                      );
                    }
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                  child: const Text('保存',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    titleCtrl.dispose();
  }

  String _formatRemind(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final diff = day.difference(today).inDays;
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '明天 $hm';
    if (diff == -1) return '昨天 $hm';
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'todo-fab',
        onPressed: () => _openEditor(),
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
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: TodoStore.notifier,
        builder: (context, todos, _) {
          if (todos.isEmpty) return _buildEmpty();
          final pending = todos.where((t) => t['done'] != true).length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Text('未完成 $pending 项',
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6))),
                    const Spacer(),
                    Text('共 ${todos.length} 项',
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.4))),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: todos.length,
                  itemBuilder: (context, i) => _buildItem(todos[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
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
            child: Icon(Icons.checklist_rounded,
                size: 44, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text('还没有待办，点右下角 + 新建',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6))),
          const SizedBox(height: 6),
          Text('可以给每件事设一个提醒时间',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4))),
        ],
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> t) {
    final id = t['id'] as String;
    final done = t['done'] == true;
    final remindRaw = t['remind_at']?.toString();
    final remind = remindRaw == null ? null : DateTime.tryParse(remindRaw);
    final overdue =
        remind != null && !done && !remind.isAfter(DateTime.now());

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: Checkbox(
          value: done,
          onChanged: (_) => TodoStore.toggle(id),
        ),
        title: Text(
          (t['title'] ?? '').toString(),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: done ? TextDecoration.lineThrough : null,
            color: done
                ? Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.45)
                : null,
          ),
        ),
        subtitle: remind == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      overdue ? Icons.notifications_active : Icons.alarm,
                      size: 14,
                      color: overdue ? _bloodBright : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      overdue
                          ? '已到时间 · ${_formatRemind(remind)}'
                          : '提醒 ${_formatRemind(remind)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: overdue ? _bloodBright : Colors.grey.shade600,
                        fontWeight:
                            overdue ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
        trailing: PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (v) {
            if (v == 'edit') _openEditor(todo: t);
            if (v == 'del') TodoStore.remove(id);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(value: 'del', child: Text('删除')),
          ],
        ),
        onTap: () => _openEditor(todo: t),
      ),
    );
  }
}

