import 'package:flutter/material.dart';

import 'habit_store.dart';

const Color _accent = Color(0xFF5B67F1);

/// 打卡页：**纯习惯打卡**（不含任何加冕 / 王室内容 —— 头衔系统在右上角入口）。
///
/// - 首次使用内置 3 条习惯：每日跑步 30min / 每日看书 30min / 每日冥想 30min
/// - 可新增、编辑、删除；点右侧圆勾打今日卡，显示连续天数
/// - 数据本机存储，登录后自动同步云端
class HabitPage extends StatefulWidget {
  const HabitPage({super.key});

  @override
  State<HabitPage> createState() => _HabitPageState();
}

class _HabitPageState extends State<HabitPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (HabitStore.habits.value.isEmpty) {
      await HabitStore.load();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static const Map<String, IconData> _iconChoices = {
    'directions_run': Icons.directions_run,
    'menu_book': Icons.menu_book,
    'self_improvement': Icons.self_improvement,
    'fitness_center': Icons.fitness_center,
    'water_drop': Icons.water_drop,
    'bedtime': Icons.bedtime,
    'code': Icons.code,
    'check_circle': Icons.check_circle,
  };

  IconData _iconOf(String? key) => _iconChoices[key] ?? Icons.check_circle;

  // ---------- 新增 / 编辑 ----------
  Future<void> _openEditor({Map<String, dynamic>? habit}) async {
    final isNew = habit == null;
    final nameCtrl =
        TextEditingController(text: habit?['name']?.toString() ?? '');
    var iconKey = habit?['icon']?.toString() ?? 'check_circle';
    var colorValue = habit?['color'] as int? ?? 0xFF5B67F1;

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
                Text(isNew ? '新增打卡习惯' : '编辑打卡习惯',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  autofocus: isNew,
                  decoration: const InputDecoration(
                    labelText: '习惯名称（如 每日跑步 30min）',
                    prefixIcon: Icon(Icons.edit_note),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('图标',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    for (final e in _iconChoices.entries)
                      GestureDetector(
                        onTap: () => setSheet(() => iconKey = e.key),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: iconKey == e.key
                                ? Color(colorValue).withValues(alpha: 0.18)
                                : Colors.transparent,
                            border: Border.all(
                              color: iconKey == e.key
                                  ? Color(colorValue)
                                  : Colors.grey.withValues(alpha: 0.3),
                              width: iconKey == e.key ? 2 : 1,
                            ),
                          ),
                          child: Icon(e.value,
                              size: 22,
                              color: iconKey == e.key
                                  ? Color(colorValue)
                                  : Colors.grey),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('颜色',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final c in const [
                      0xFFE53935,
                      0xFF5B67F1,
                      0xFF06B6D4,
                      0xFF43A047,
                      0xFFFB8C00,
                      0xFF8E24AA,
                    ])
                      GestureDetector(
                        onTap: () => setSheet(() => colorValue = c),
                        child: Container(
                          margin: const EdgeInsets.only(right: 10),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: colorValue == c
                                ? Border.all(color: Colors.white, width: 2)
                                : null,
                          ),
                          child: colorValue == c
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(sheetCtx).showSnackBar(
                            const SnackBar(content: Text('先给习惯起个名字')));
                        return;
                      }
                      if (isNew) {
                        await HabitStore.add(
                            name: name, icon: iconKey, color: colorValue);
                      } else {
                        await HabitStore.rename(habit['id'] as String, name);
                      }
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    },
                    child: const Text('保存',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: HabitStore.habits,
      builder: (context, habits, _) =>
          ValueListenableBuilder<Set<String>>(
        valueListenable: HabitStore.logs,
        builder: (context, _, __) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
          children: [
            _buildTodayCard(habits.length),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('我的习惯',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                const Text('点击圆勾打卡 · 长按可编辑/删除',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            ...habits.map(_buildHabitTile),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增习惯'),
            ),
          ],
        ),
      ),
    );
  }

  /// 今日进度卡（纯习惯维度，不含任何头衔内容）
  Widget _buildTodayCard(int total) {
    final done = HabitStore.todayDone;
    final progress = total == 0 ? 0.0 : done / total;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8EAF6), Color(0xFFDDE3FB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available_rounded,
                  color: _accent, size: 24),
              const SizedBox(width: 8),
              const Text('今日进度',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2A2E5C))),
              const Spacer(),
              Text('$done / $total',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _accent)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.7),
              color: _accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            total == 0
                ? '先添加一个习惯吧'
                : (done == total
                    ? '今天全部完成，保持住 💪'
                    : '还有 ${total - done} 项待打卡'),
            style: TextStyle(
                fontSize: 12.5,
                color: const Color(0xFF2A2E5C).withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitTile(Map<String, dynamic> h) {
    final id = h['id'] as String;
    final name = h['name']?.toString() ?? '';
    final color = Color((h['color'] as int?) ?? 0xFF5B67F1);
    final done = HabitStore.isChecked(id);
    final streak = HabitStore.streakOf(id);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        onLongPress: () => _showHabitActions(h),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_iconOf(h['icon']?.toString()), color: color, size: 22),
        ),
        title: Text(name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: Text(
          streak > 0 ? '连续 $streak 天' : '还没开始',
          style: TextStyle(
              fontSize: 12,
              color: streak > 0 ? color : Colors.grey.shade500),
        ),
        trailing: GestureDetector(
          onTap: () => HabitStore.toggleToday(id),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? color : Colors.transparent,
              border: Border.all(
                  color: done ? color : Colors.grey.withValues(alpha: 0.4),
                  width: 2),
            ),
            child: Icon(done ? Icons.check : Icons.add,
                color: done ? Colors.white : Colors.grey, size: 22),
          ),
        ),
        onTap: () => HabitStore.toggleToday(id),
      ),
    );
  }

  void _showHabitActions(Map<String, dynamic> h) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _openEditor(habit: h);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
              title: Text('删除「${h['name']}」',
                  style: TextStyle(color: Colors.red.shade400)),
              onTap: () {
                Navigator.pop(sheetCtx);
                HabitStore.remove(h['id'] as String);
                _snack('已删除「${h['name']}」');
              },
            ),
          ],
        ),
      ),
    );
  }
}


