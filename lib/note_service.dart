import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'local_notes.dart';

/// 游客模式下调用云端专属功能（加冕签到等）时抛出。
class GuestNotAllowedException implements Exception {
  final String message;
  const GuestNotAllowedException(this.message);
  @override
  String toString() => message;
}

class NoteService {
  NoteService._();
  static final NoteService instance = NoteService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ---------- 初始化 ----------
  /// Supabase 是否已初始化完成。未完成时不能访问 Supabase.instance
  /// （会抛 "You must call Supabase.initialize"），界面据此降级到登录页。
  static bool ready = false;

  static Future<void> init() async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
    ready = true;
  }

  // ---------- 游客模式 ----------
  static const String _guestKey = 'guest_mode';

  /// 游客模式开关（持久化在本机）。界面监听它，实时切换登录页 / 主界面。
  static final ValueNotifier<bool> guestNotifier = ValueNotifier<bool>(false);

  static bool get isGuest => guestNotifier.value;

  /// 启动时恢复上次的模式选择。
  ///
  /// 自愈：如果本机已有登录会话，游客标志一律作废 —— 早期版本登录时没清这个
  /// 标志，会留下"已登录却被当游客"的脏状态（表现为王室页报
  /// 「游客模式不支持加冕签到」、聊天室/社区误判未登录）。
  static Future<void> loadGuestState() async {
    final prefs = await SharedPreferences.getInstance();
    var guest = prefs.getBool(_guestKey) ?? false;
    if (guest && Supabase.instance.client.auth.currentSession != null) {
      guest = false;
      await prefs.setBool(_guestKey, false);
    }
    guestNotifier.value = guest;
  }

  /// 进入游客模式：不登录、不联网，数据只存本机
  Future<void> enterGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guestKey, true);
    guestNotifier.value = true;
  }

  /// 退出游客模式（回到登录页）。本地笔记仍留在本机，但登录后读的是云端数据，
  /// 不会自动上传 —— 需要保留的话用列表里的「导出/分享」。
  Future<void> exitGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guestKey, false);
    guestNotifier.value = false;
  }

  // ---------- 认证 ----------
  bool get isLoggedIn => _client.auth.currentSession != null;
  String? get userId => _client.auth.currentUser?.id;
  String? get email => _client.auth.currentUser?.email;

  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    // 登录成功：若之前是游客模式，清掉游客标记（否则退出登录会走错分支）
    if (isGuest) await exitGuestMode();
  }

  Future<void> signUp(String email, String password) async {
    await _client.auth.signUp(email: email, password: password);
  }

  /// 退出：真登录就走 Supabase 登出；游客模式只清游客标记。
  /// 两者都做，避免"游客 + 已登录"叠加时退不干净。
  Future<void> signOut() async {
    if (_client.auth.currentSession != null) {
      await _client.auth.signOut();
    }
    if (isGuest) {
      await exitGuestMode();
    }
  }

  // ---------- 账户 ----------
  /// 修改密码（需已登录）
  Future<void> updatePassword(String newPassword) async {
    if (isGuest) throw const GuestNotAllowedException('游客模式没有账号，无法修改密码');
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// 发送重置密码邮件（忘记密码流程）
  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  // ---------- 笔记 CRUD ----------
  /// 拉取正常笔记（排除回收站），置顶优先，再按更新时间倒序。
  /// 游客模式走本机存储。
  Future<List<Map<String, dynamic>>> fetchNotes() async {
    if (isGuest) return LocalNotes.fetchNotes();
    final res = await _client
        .from('notes')
        .select()
        .isFilter('deleted_at', null)
        .order('pinned', ascending: false)
        .order('updated_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// 拉取回收站里的笔记（已软删除），按删除时间倒序。
  Future<List<Map<String, dynamic>>> fetchTrash() async {
    if (isGuest) return LocalNotes.fetchTrash();
    final res = await _client
        .from('notes')
        .select()
        .not('deleted_at', 'is', null)
        .order('deleted_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<Map<String, dynamic>> createNote({
    required String title,
    required String content,
    List<String> tags = const [],
    bool pinned = false,
  }) async {
    if (isGuest) {
      return LocalNotes.create(
          title: title, content: content, tags: tags, pinned: pinned);
    }
    final res = await _client.from('notes').insert({
      'user_id': userId,
      'title': title,
      'content': content,
      'tags': tags,
      'pinned': pinned,
    }).select().single();
    return Map<String, dynamic>.from(res);
  }

  Future<void> updateNote({
    required String id,
    required String title,
    required String content,
    List<String> tags = const [],
    bool pinned = false,
  }) async {
    if (isGuest) {
      await LocalNotes.update(
          id: id, title: title, content: content, tags: tags, pinned: pinned);
      return;
    }
    // updated_at 由数据库触发器自动更新，客户端不手动传
    await _client.from('notes').update({
      'title': title,
      'content': content,
      'tags': tags,
      'pinned': pinned,
    }).eq('id', id);
  }

  /// 软删除：笔记移入回收站（不物理删除）
  Future<void> deleteNote(String id) async {
    if (isGuest) {
      await LocalNotes.setDeleted(id, DateTime.now().toUtc().toIso8601String());
      return;
    }
    await _client.from('notes').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// 恢复：从回收站还原笔记
  Future<void> restoreNote(String id) async {
    if (isGuest) {
      await LocalNotes.setDeleted(id, null);
      return;
    }
    await _client.from('notes').update({'deleted_at': null}).eq('id', id);
  }

  /// 永久删除：从回收站彻底清除
  Future<void> purgeNote(String id) async {
    if (isGuest) {
      await LocalNotes.purge(id);
      return;
    }
    await _client.from('notes').delete().eq('id', id);
  }

  // ---------- 实时同步 ----------
  /// 订阅 notes 表变化，返回可取消的订阅流。
  /// 任何端增删改笔记，这里都会收到通知，实现多端实时互通。
  /// 游客模式没有云端数据，返回 null（不建立连接）。
  RealtimeChannel? subscribeNotes({
    required void Function() onChanged,
    String? forUserId,
  }) {
    if (isGuest) return null;
    final channel = _client.channel('notes-changes');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'notes',
      callback: (payload) {
        // 可选：只响应当前用户的笔记变化
        final newUserId = payload.newRecord['user_id']?.toString();
        final oldUserId = payload.oldRecord['user_id']?.toString();
        if (forUserId != null &&
            newUserId != forUserId &&
            oldUserId != forUserId) {
          return;
        }
        onChanged();
      },
    ).subscribe();

    return channel;
  }

  // ---------- 加冕签到（云端专属） ----------
  /// 拉取当前用户的签到状态；从未签到过则返回 null。
  Future<Map<String, dynamic>?> fetchCheckin() async {
    if (isGuest) throw const GuestNotAllowedException('游客模式不支持加冕签到');
    final res = await _client
        .from('checkins')
        .select('days, last_checkin')
        .maybeSingle();
    return res == null ? null : Map<String, dynamic>.from(res);
  }

  /// PostgREST 对 `RETURNS TABLE` 的 RPC 一律返回 JSON **数组**（哪怕只有一行，
  /// 见 postgrest 文档 / supabase#46525）。这里把「数组首行」和「单对象」两种
  /// 形状归一成 Map，避免直接 Map.from(List) 抛 `_TypeError`。
  static Map<String, dynamic> normalizeRpcRow(dynamic res) {
    final dynamic row = res is List ? (res.isEmpty ? null : res.first) : res;
    if (row is! Map) {
      throw StateError('服务端返回了意外的数据形状：$res');
    }
    return Map<String, dynamic>.from(row);
  }

  /// 签到（服务端原子处理：今天未签则 +1 天，已签则原样返回）。
  /// 返回最新 {days, last_checkin}。游客模式不可用。
  Future<Map<String, dynamic>> checkIn() async {
    if (isGuest) throw const GuestNotAllowedException('游客模式不支持加冕签到');
    final res = await _client.rpc('checkin');
    return normalizeRpcRow(res);
  }

  /// 订阅 checkins 表变化，跨端实时同步签到进度。游客模式返回 null。
  RealtimeChannel? subscribeCheckins({
    required void Function() onChanged,
    String? forUserId,
  }) {
    if (isGuest) return null;
    final channel = _client.channel('checkins-changes');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'checkins',
      callback: (payload) {
        final newUserId = payload.newRecord['user_id']?.toString();
        final oldUserId = payload.oldRecord['user_id']?.toString();
        if (forUserId != null &&
            newUserId != forUserId &&
            oldUserId != forUserId) {
          return;
        }
        onChanged();
      },
    ).subscribe();
    return channel;
  }
}
