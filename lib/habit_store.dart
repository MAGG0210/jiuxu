import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 习惯打卡数据层。
///
/// - 首次使用自动内置 3 条预设习惯（跑步 / 看书 / 冥想）
/// - 未登录：只存本机
/// - 已登录：本机 + 云端 `habits` / `habit_logs` 表同步
///
/// 习惯字段：id / name / icon / color / created_at / archived
/// 打卡记录：{ 'habit_id': ..., 'date': '2026-09-27' } 集合
class HabitStore {
  HabitStore._();

  static const String _keyHabits = 'habits_v1';
  static const String _keyLogs = 'habit_logs_v1';

  static final Random _rng = Random();

  static final ValueNotifier<List<Map<String, dynamic>>> habits =
      ValueNotifier<List<Map<String, dynamic>>>(<Map<String, dynamic>>[]);

  /// 打卡记录：`habitId|yyyy-MM-dd` 的集合
  static final ValueNotifier<Set<String>> logs =
      ValueNotifier<Set<String>>(<String>{});

  /// 是否已登录（未初始化 Supabase 时——例如单元测试——安全返回 false）
  static bool get _loggedIn {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  static String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  static String _newId() =>
      'habit-${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(0x7FFFFFFF).toRadixString(16)}';

  /// 本地日期（yyyy-MM-dd）
  static String dateKey([DateTime? d]) {
    final t = d ?? DateTime.now();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  static String logKey(String habitId, String date) => '$habitId|$date';

  /// 内置预设习惯（首次使用）
  static List<Map<String, dynamic>> _presets() {
    final now = DateTime.now().toIso8601String();
    return [
      {
        'id': _newId(),
        'name': '每日跑步 30min',
        'icon': 'directions_run',
        'color': 0xFFE53935,
        'created_at': now,
        'archived': false,
      },
      {
        'id': _newId(),
        'name': '每日看书 30min',
        'icon': 'menu_book',
        'color': 0xFF5B67F1,
        'created_at': now,
        'archived': false,
      },
      {
        'id': _newId(),
        'name': '每日冥想 30min',
        'icon': 'self_improvement',
        'color': 0xFF06B6D4,
        'created_at': now,
        'archived': false,
      },
    ];
  }

  // ---------- 读取 ----------
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // 习惯
    List<Map<String, dynamic>> list = [];
    final rawHabits = prefs.getString(_keyHabits);
    if (rawHabits != null && rawHabits.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHabits);
        if (decoded is List) {
          list = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {
        list = [];
      }
    }
    // 首次使用：写入 3 条预设
    if (list.isEmpty) {
      list = _presets();
      await prefs.setString(_keyHabits, jsonEncode(list));
    }
    habits.value = _sorted(list);

    // 打卡记录
    final rawLogs = prefs.getString(_keyLogs);
    final set = <String>{};
    if (rawLogs != null && rawLogs.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawLogs);
        if (decoded is List) set.addAll(decoded.map((e) => e.toString()));
      } catch (_) {/* 忽略损坏数据 */}
    }
    logs.value = set;

    // 已登录：拉云端合并
    if (_loggedIn) {
      await pullFromCloud();
    }
  }

  static List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> list) {
    final copy = [...list];
    copy.sort((a, b) => (a['created_at'] ?? '')
        .toString()
        .compareTo((b['created_at'] ?? '').toString()));
    return copy;
  }

  static Future<void> _persistHabits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHabits, jsonEncode(habits.value));
  }

  static Future<void> _persistLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLogs, jsonEncode(logs.value.toList()));
  }

  // ---------- 习惯增删改 ----------
  static Future<void> add({
    required String name,
    String icon = 'check_circle',
    int color = 0xFF5B67F1,
  }) async {
    final habit = <String, dynamic>{
      'id': _newId(),
      'name': name,
      'icon': icon,
      'color': color,
      'created_at': DateTime.now().toIso8601String(),
      'archived': false,
    };
    habits.value = _sorted([...habits.value, habit]);
    await _persistHabits();
    if (_loggedIn) {
      try {
        await Supabase.instance.client.from('habits').insert({
          'id': habit['id'],
          'user_id': _uid,
          'name': name,
          'icon': icon,
          'color': color,
        });
      } catch (_) {/* 云端失败不影响本地 */}
    }
  }

  static Future<void> rename(String id, String name) async {
    habits.value = _sorted([
      for (final h in habits.value)
        if (h['id'] == id) {...h, 'name': name} else h
    ]);
    await _persistHabits();
    if (_loggedIn) {
      try {
        await Supabase.instance.client
            .from('habits')
            .update({'name': name}).eq('id', id);
      } catch (_) {}
    }
  }

  static Future<void> remove(String id) async {
    habits.value = _sorted(habits.value.where((h) => h['id'] != id).toList());
    logs.value = logs.value.where((k) => !k.startsWith('$id|')).toSet();
    await _persistHabits();
    await _persistLogs();
    if (_loggedIn) {
      try {
        await Supabase.instance.client.from('habits').delete().eq('id', id);
      } catch (_) {}
    }
  }

  // ---------- 打卡 ----------
  static bool isChecked(String habitId, [DateTime? day]) =>
      logs.value.contains(logKey(habitId, dateKey(day)));

  static Future<void> toggleToday(String habitId) async {
    final date = dateKey();
    final key = logKey(habitId, date);
    final next = {...logs.value};
    final adding = !next.contains(key);
    if (adding) {
      next.add(key);
    } else {
      next.remove(key);
    }
    logs.value = next;
    await _persistLogs();
    if (_loggedIn) {
      try {
        if (adding) {
          await Supabase.instance.client.from('habit_logs').insert({
            'user_id': _uid,
            'habit_id': habitId,
            'day': date,
          });
        } else {
          await Supabase.instance.client
              .from('habit_logs')
              .delete()
              .eq('habit_id', habitId)
              .eq('day', date);
        }
      } catch (_) {}
    }
  }

  /// 今日已打卡数量 / 习惯总数
  static int get todayDone =>
      habits.value.where((h) => isChecked(h['id'] as String)).length;

  static int get habitCount => habits.value.length;

  /// 连续打卡天数（以今天或昨天为起点往回数，任一习惯都算）
  static int streakOf(String habitId) {
    var streak = 0;
    var day = DateTime.now();
    // 今天没打卡不算断（从昨天开始数）
    if (!isChecked(habitId, day)) {
      day = day.subtract(const Duration(days: 1));
      if (!isChecked(habitId, day)) return 0;
    }
    while (isChecked(habitId, day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // ---------- 云端同步 ----------
  static Future<void> pullFromCloud() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('habits')
          .select('id, name, icon, color, created_at')
          .eq('user_id', uid);
      if (rows.isNotEmpty) {
        // 云端为准，合并本机独有的（按 id 去重）
        final cloud = List<Map<String, dynamic>>.from(rows)
            .map((e) => {...e, 'archived': false})
            .toList();
        final ids = cloud.map((e) => e['id'].toString()).toSet();
        final localOnly =
            habits.value.where((h) => !ids.contains(h['id'].toString()));
        habits.value = _sorted([...cloud, ...localOnly]);
        await _persistHabits();
      }

      final logRows = await Supabase.instance.client
          .from('habit_logs')
          .select('habit_id, day')
          .eq('user_id', uid);
      final set = {...logs.value};
      for (final r in logRows) {
        set.add(logKey(r['habit_id'].toString(), r['day'].toString()));
      }
      logs.value = set;
      await _persistLogs();
    } catch (_) {/* 云端不可用时保持本地数据 */}
  }
}
