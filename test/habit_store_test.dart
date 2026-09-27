import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/habit_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 习惯打卡数据层：预设习惯、打卡开关、连续天数、增删改、持久化。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HabitStore.habits.value = <Map<String, dynamic>>[];
    HabitStore.logs.value = <String>{};
  });

  test('首次加载自动内置 3 条预设习惯', () async {
    await HabitStore.load();
    expect(HabitStore.habits.value.length, 3);
    final names = HabitStore.habits.value.map((h) => h['name']).toList();
    expect(
      names,
      containsAll(['每日跑步 30min', '每日看书 30min', '每日冥想 30min']),
    );
  });

  test('打卡 / 取消：今日状态与计数跟着变', () async {
    await HabitStore.load();
    final id = HabitStore.habits.value.first['id'] as String;

    expect(HabitStore.isChecked(id), false);
    await HabitStore.toggleToday(id);
    expect(HabitStore.isChecked(id), true);
    expect(HabitStore.todayDone, 1);

    await HabitStore.toggleToday(id);
    expect(HabitStore.isChecked(id), false);
    expect(HabitStore.todayDone, 0);
  });

  test('新增 / 重命名 / 删除习惯', () async {
    await HabitStore.load();
    await HabitStore.add(name: '写代码 1h', icon: 'code', color: 0xFF43A047);
    expect(HabitStore.habits.value.length, 4);

    final added =
        HabitStore.habits.value.firstWhere((h) => h['name'] == '写代码 1h');
    await HabitStore.rename(added['id'] as String, '写代码 2h');
    expect(HabitStore.habits.value.any((h) => h['name'] == '写代码 2h'), true);

    await HabitStore.remove(added['id'] as String);
    expect(HabitStore.habits.value.length, 3);
  });

  test('连续天数：今天 + 昨天都打卡 → 连续 2 天；断一天就归零', () async {
    final today = HabitStore.dateKey();
    final yesterday =
        HabitStore.dateKey(DateTime.now().subtract(const Duration(days: 1)));
    SharedPreferences.setMockInitialValues({
      'habits_v1': jsonEncode([
        {
          'id': 'h1',
          'name': '跑步',
          'icon': 'directions_run',
          'color': 0xFFE53935,
          'created_at': '2026-01-01T00:00:00.000',
          'archived': false,
        }
      ]),
      'habit_logs_v1': jsonEncode(['h1|$today', 'h1|$yesterday']),
    });
    await HabitStore.load();
    expect(HabitStore.streakOf('h1'), 2);

    // 把昨天的记录删掉 → 只剩今天，连续天数为 1
    SharedPreferences.setMockInitialValues({
      'habits_v1': jsonEncode([
        {
          'id': 'h1',
          'name': '跑步',
          'icon': 'directions_run',
          'color': 0xFFE53935,
          'created_at': '2026-01-01T00:00:00.000',
          'archived': false,
        }
      ]),
      'habit_logs_v1': jsonEncode(['h1|$today']),
    });
    await HabitStore.load();
    expect(HabitStore.streakOf('h1'), 1);
  });

  test('删除习惯会同时清掉它的打卡记录', () async {
    await HabitStore.load();
    final id = HabitStore.habits.value.first['id'] as String;
    await HabitStore.toggleToday(id);
    expect(HabitStore.logs.value.length, 1);

    await HabitStore.remove(id);
    expect(HabitStore.logs.value.length, 0);
  });

  test('持久化：重新 load 后新增的习惯还在', () async {
    await HabitStore.load();
    await HabitStore.add(name: '冥想 10min');
    HabitStore.habits.value = <Map<String, dynamic>>[];
    await HabitStore.load();
    expect(
      HabitStore.habits.value.any((h) => h['name'] == '冥想 10min'),
      true,
    );
  });
}

