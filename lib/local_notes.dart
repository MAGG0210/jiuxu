import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 游客模式的本地笔记存储：在 SharedPreferences 里存一份 JSON。
///
/// 刻意不复用 Supabase 数据层 —— 游客数据只在本机，卸载应用即消失，
/// 不参与任何云端同步（云备份与加冕签到都不可用）。
class LocalNotes {
  LocalNotes._();

  static const String _key = 'guest_notes_v1';
  static const String guestUserId = 'guest';

  static final Random _rng = Random();

  /// 时间戳 + 随机后缀：同一毫秒内连续新建不会撞 id
  static String _newId() =>
      'local-${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(0x7FFFFFFF).toRadixString(16)}';

  static Future<List<Map<String, dynamic>>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      // 本地数据损坏时不让界面崩，当作空库处理
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> _write(List<Map<String, dynamic>> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(notes));
  }

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// 正常笔记（排除回收站）：置顶优先，再按更新时间倒序（与云端查询同序）
  static Future<List<Map<String, dynamic>>> fetchNotes() async {
    final list =
        (await _read()).where((n) => n['deleted_at'] == null).toList();
    list.sort((a, b) {
      final pa = a['pinned'] == true ? 1 : 0;
      final pb = b['pinned'] == true ? 1 : 0;
      if (pa != pb) return pb - pa;
      return (b['updated_at'] ?? '')
          .toString()
          .compareTo((a['updated_at'] ?? '').toString());
    });
    return list;
  }

  /// 回收站：按删除时间倒序
  static Future<List<Map<String, dynamic>>> fetchTrash() async {
    final list =
        (await _read()).where((n) => n['deleted_at'] != null).toList();
    list.sort((a, b) => (b['deleted_at'] ?? '')
        .toString()
        .compareTo((a['deleted_at'] ?? '').toString()));
    return list;
  }

  static Future<Map<String, dynamic>> create({
    required String title,
    required String content,
    List<String> tags = const [],
    bool pinned = false,
  }) async {
    final all = await _read();
    final now = _nowIso();
    final note = <String, dynamic>{
      'id': _newId(),
      'user_id': guestUserId,
      'title': title,
      'content': content,
      'tags': tags,
      'pinned': pinned,
      'deleted_at': null,
      'created_at': now,
      'updated_at': now,
    };
    all.add(note);
    await _write(all);
    return note;
  }

  static Future<void> update({
    required String id,
    required String title,
    required String content,
    List<String> tags = const [],
    bool pinned = false,
  }) async {
    final all = await _read();
    for (final n in all) {
      if (n['id'] == id) {
        n['title'] = title;
        n['content'] = content;
        n['tags'] = tags;
        n['pinned'] = pinned;
        n['updated_at'] = _nowIso();
      }
    }
    await _write(all);
  }

  /// 软删除 / 恢复：deletedAt 为 null 表示从回收站恢复
  static Future<void> setDeleted(String id, String? deletedAt) async {
    final all = await _read();
    for (final n in all) {
      if (n['id'] == id) {
        n['deleted_at'] = deletedAt;
        n['updated_at'] = _nowIso();
      }
    }
    await _write(all);
  }

  /// 永久删除
  static Future<void> purge(String id) async {
    final all = await _read();
    all.removeWhere((n) => n['id'] == id);
    await _write(all);
  }

  /// 本地数据条数（用于退出游客模式前的提示）
  static Future<int> count() async => (await _read()).length;

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

