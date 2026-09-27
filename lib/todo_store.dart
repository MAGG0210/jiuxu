import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 待办数据层：本机存储（与登录/游客状态无关 —— 待办属于这台设备上的个人清单）。
///
/// 字段：id / title / done / remind_at(ISO|null) / notified / created_at
class TodoStore {
  TodoStore._();

  static const String _key = 'todos_v1';

  static final Random _rng = Random();

  /// 时间戳 + 随机后缀：同一毫秒内连续新建也不会撞 id
  /// （纯时间戳在 Windows 上精度只到毫秒，快速连点会重复）
  static String _newId() =>
      'todo-${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(0x7FFFFFFF).toRadixString(16)}';

  /// 全局清单，界面用 ValueListenableBuilder 监听即可自动刷新
  static final ValueNotifier<List<Map<String, dynamic>>> notifier =
      ValueNotifier<List<Map<String, dynamic>>>(<Map<String, dynamic>>[]);

  static List<Map<String, dynamic>> get todos => notifier.value;

  static String _nowIso() => DateTime.now().toIso8601String();

  /// 启动时从本机读取
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    var list = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {
        // 数据损坏当作空清单，不让界面崩
        list = <Map<String, dynamic>>[];
      }
    }
    notifier.value = _sorted(list);
    // 首次使用：预置 3 条示例待办（只做一次）
    await _seedExamplesIfNeeded();
    // 登录状态：拉云端待办合并（本机没有的补回来，本机独有的补推上去）
    if (_loggedIn) await pullFromCloud();
  }

  static const String _seedKey = 'todos_seeded_v1';

  /// 预置示例：妈妈生日 / 爸爸生日 / 过年时间（下一个春节那天上午 9 点提醒）
  static Future<void> _seedExamplesIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seedKey) == true) return;
    await prefs.setBool(_seedKey, true);
    if (notifier.value.isNotEmpty) return;
    await add(title: '妈妈生日');
    await add(title: '爸爸生日');
    await add(title: '过年时间', remindAt: DateTime(2027, 2, 6, 9, 0));
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(notifier.value));
  }

  // ---------- 云端同步（本地优先，登录后自动备份） ----------
  static bool get _loggedIn {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  static String? get _uid {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _pushUpsert(Map<String, dynamic> t) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('todos').upsert({
        'id': t['id'].toString(),
        'user_id': uid,
        'title': t['title'],
        'done': t['done'] == true,
        'remind_at': t['remind_at'],
      });
    } catch (_) {/* 云端不可用不影响本地 */}
  }

  static Future<void> _pushDelete(String id) async {
    if (!_loggedIn) return;
    try {
      await Supabase.instance.client.from('todos').delete().eq('id', id);
    } catch (_) {}
  }

  /// 登录后拉云端待办合并（本机独有的补推上去），换设备登录即可拿回全部
  static Future<void> pullFromCloud() async {
    if (!_loggedIn) return;
    try {
      final rows = await Supabase.instance.client.from('todos').select();
      if (rows.isEmpty) {
        for (final t in notifier.value) {
          await _pushUpsert(t);
        }
        return;
      }
      final cloud = List<Map<String, dynamic>>.from(rows)
          .map((r) => <String, dynamic>{
                'id': r['id'].toString(),
                'title': r['title'],
                'done': r['done'] == true,
                'remind_at': r['remind_at'],
                'notified': false,
                'created_at':
                    r['created_at'] ?? DateTime.now().toIso8601String(),
              })
          .toList();
      final ids = cloud.map((e) => e['id'].toString()).toSet();
      final localOnly = notifier.value
          .where((t) => !ids.contains(t['id'].toString()))
          .toList();
      for (final t in localOnly) {
        await _pushUpsert(t);
      }
      notifier.value = _sorted([...cloud, ...localOnly]);
      await _persist();
    } catch (_) {}
  }

  /// 排序：未完成在前；同组内按提醒时间升序（无提醒的排后面，再按创建时间）
  static List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> list) {
    final copy = [...list];
    copy.sort((a, b) {
      final da = a['done'] == true ? 1 : 0;
      final db = b['done'] == true ? 1 : 0;
      if (da != db) return da - db;
      final ra = a['remind_at']?.toString();
      final rb = b['remind_at']?.toString();
      if (ra != null && rb != null) return ra.compareTo(rb);
      if (ra != null) return -1;
      if (rb != null) return 1;
      return (a['created_at'] ?? '').toString().compareTo((b['created_at'] ?? '').toString());
    });
    return copy;
  }

  static Future<void> add({required String title, DateTime? remindAt}) async {
    final item = <String, dynamic>{
      'id': _newId(),
      'title': title,
      'done': false,
      'remind_at': remindAt?.toIso8601String(),
      'notified': false,
      'created_at': _nowIso(),
    };
    notifier.value = _sorted([...notifier.value, item]);
    await _persist();
    await _pushUpsert(item);
  }

  static Future<void> toggle(String id) async {
    notifier.value = _sorted([
      for (final t in notifier.value)
        if (t['id'] == id)
          {
            ...t,
            'done': !(t['done'] == true),
            // 完成就撤销提醒标记，重新打开时还能再提醒
            'notified': false,
          }
        else
          t
    ]);
    await _persist();
    final item =
        notifier.value.firstWhere((t) => t['id'] == id, orElse: () => {});
    if (item.isNotEmpty) await _pushUpsert(item);
  }

  static Future<void> update({
    required String id,
    String? title,
    DateTime? remindAt,
    bool clearRemind = false,
  }) async {
    final next = <Map<String, dynamic>>[];
    for (final t in notifier.value) {
      if (t['id'] != id) {
        next.add(t);
        continue;
      }
      final edited = <String, dynamic>{...t};
      if (title != null) edited['title'] = title;
      if (clearRemind) {
        edited['remind_at'] = null;
      } else if (remindAt != null) {
        edited['remind_at'] = remindAt.toIso8601String();
      }
      // 改了提醒时间就允许再次提醒
      edited['notified'] = false;
      next.add(edited);
    }
    notifier.value = _sorted(next);
    await _persist();
    final item =
        notifier.value.firstWhere((t) => t['id'] == id, orElse: () => {});
    if (item.isNotEmpty) await _pushUpsert(item);
  }

  static Future<void> remove(String id) async {
    notifier.value =
        _sorted(notifier.value.where((t) => t['id'] != id).toList());
    await _persist();
    await _pushDelete(id);
  }

  static Future<void> markNotified(String id) async {
    notifier.value = [
      for (final t in notifier.value)
        if (t['id'] == id) {...t, 'notified': true} else t
    ];
    await _persist();
  }

  /// 已到提醒时间、尚未提醒、且未完成的待办
  static List<Map<String, dynamic>> dueNow() {
    final now = DateTime.now();
    return notifier.value.where((t) {
      if (t['done'] == true || t['notified'] == true) return false;
      final raw = t['remind_at']?.toString();
      if (raw == null) return false;
      final at = DateTime.tryParse(raw);
      if (at == null) return false;
      return !at.isAfter(now);
    }).toList();
  }

  /// 未完成条数
  static int get pendingCount =>
      notifier.value.where((t) => t['done'] != true).length;
}
