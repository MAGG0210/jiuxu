import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ranks.dart';

/// 用户资料 + 偏好设置。
///
/// 存储策略：
/// - 未登录 / 游客：只写本机（shared_preferences）
/// - 已登录：写本机 **并** 同步到云端 `profiles` 表（昵称 / 头像 / 头衔），
///   头像图片上传到 Storage 的 `avatars` 桶，路径 `<uid>/avatar.png`
class ProfileStore {
  ProfileStore._();

  static const String _keyProfile = 'profile_v1';
  static const String _keySettings = 'settings_v1';

  /// 全局资料（头像/昵称/头衔）—— 主页、侧边栏、聊天室都监听它，改完即时刷新
  static final ValueNotifier<Map<String, dynamic>> profile =
      ValueNotifier<Map<String, dynamic>>(<String, dynamic>{});

  /// 偏好设置
  static final ValueNotifier<Map<String, dynamic>> settings =
      ValueNotifier<Map<String, dynamic>>(Map<String, dynamic>.from(defaults));

  static const Map<String, dynamic> defaults = <String, dynamic>{
    // 通用
    'fontScale': 1.0, // 0.85 / 1.0 / 1.15 / 1.3
    'sound': true,
    'vibrate': true,
    // 通知
    'notifyCheckin': true,
    'notifyTodo': true,
    'notifyReview': true,
    'notifyChat': true,
    // 隐私
    'checkinVisibility': 'public', // public / friends / private
    'cloudSync': true,
    'dailyReviewAt': '21:00',
  };

  // ---------- 读取 / 写入 ----------
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // 资料
    final rawProfile = prefs.getString(_keyProfile);
    if (rawProfile != null && rawProfile.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawProfile);
        if (decoded is Map) {
          profile.value = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {/* 损坏则忽略 */}
    }
    // 设置（与默认值合并，保证新增开关有值）
    final rawSettings = prefs.getString(_keySettings);
    final merged = Map<String, dynamic>.from(defaults);
    if (rawSettings != null && rawSettings.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSettings);
        if (decoded is Map) merged.addAll(Map<String, dynamic>.from(decoded));
      } catch (_) {/* 损坏则用默认 */}
    }
    settings.value = merged;
  }

  static Future<void> _persistProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProfile, jsonEncode(profile.value));
  }

  static Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySettings, jsonEncode(settings.value));
  }

  static Future<void> setSetting(String key, Object? value) async {
    settings.value = {...settings.value, key: value};
    await _persistSettings();
  }

  // ---------- 便利读取 ----------
  static String get nickname {
    final n = profile.value['nickname']?.toString().trim();
    if (n != null && n.isNotEmpty) return n;
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return '无名者';
  }

  static String? get avatarB64 {
    final v = profile.value['avatar_b64']?.toString();
    return (v == null || v.isEmpty) ? null : v;
  }

  static String? get avatarUrl {
    final v = profile.value['avatar_url']?.toString();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// 网络头像（云端）优先，其次本地裁剪后的图
  static ImageProvider? get avatarImage {
    final url = avatarUrl;
    if (url != null) return NetworkImage(url);
    final b64 = avatarB64;
    if (b64 != null) {
      try {
        return MemoryImage(base64Decode(b64));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String get title => rankOf(int.tryParse('${profile.value['days'] ?? 0}') ?? 0);

  // ---------- 修改资料 ----------
  static Future<void> updateLocal({
    String? nickname,
    Uint8List? avatarBytes,
    int? days,
    String? title,
  }) async {
    final next = Map<String, dynamic>.from(profile.value);
    if (nickname != null) next['nickname'] = nickname;
    if (avatarBytes != null) next['avatar_b64'] = base64Encode(avatarBytes);
    if (days != null) next['days'] = days;
    if (title != null) next['title'] = title;
    profile.value = next;
    await _persistProfile();
  }

  /// 登录状态下把资料推到云端（昵称 / 头像 URL / 头衔天数）
  static Future<void> pushToCloud({Uint8List? avatarBytes}) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return; // 未登录：只留本机

    String? avatarUrl = avatarUrlOf(profile.value);
    if (avatarBytes != null) {
      final path = '$uid/avatar.png';
      await client.storage.from('avatars').uploadBinary(
            path,
            avatarBytes,
            fileOptions: const FileOptions(
                contentType: 'image/png', upsert: true),
          );
      avatarUrl = client.storage.from('avatars').getPublicUrl(path);
      // 加时间戳，避免 CDN 缓存旧图
      avatarUrl = '$avatarUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    }

    await client.from('profiles').upsert({
      'user_id': uid,
      'nickname': nickname,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      'title': title,
      'chat_days': int.tryParse('${profile.value['days'] ?? 0}') ?? 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    if (avatarUrl != null) {
      profile.value = {...profile.value, 'avatar_url': avatarUrl};
      await _persistProfile();
    }
  }

  static String? avatarUrlOf(Map<String, dynamic> p) {
    final v = p['avatar_url']?.toString();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// 登录后从云端拉一次资料（昵称 / 头像 / 头衔天数）
  static Future<void> pullFromCloud() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    final row = await client
        .from('profiles')
        .select('nickname, avatar_url, title, chat_days')
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) {
      // 云端还没有记录（老账号），用本地资料建一条
      await pushToCloud();
      return;
    }
    final next = Map<String, dynamic>.from(profile.value);
    if (row['nickname'] != null) next['nickname'] = row['nickname'];
    if (row['avatar_url'] != null) next['avatar_url'] = row['avatar_url'];
    if (row['chat_days'] != null) next['days'] = row['chat_days'];
    profile.value = next;
    await _persistProfile();
  }

  /// 退出登录时清掉云端身份相关字段（保留本机图片，方便下次登录复用）
  static Future<void> clearCloudFields() async {
    final next = Map<String, dynamic>.from(profile.value)
      ..remove('avatar_url')
      ..remove('days');
    profile.value = next;
    await _persistProfile();
  }

  // ---------- 头像处理 ----------
  /// 居中裁成正方形并缩放到 [size]，返回 PNG 字节（跨端一致，无需原生裁剪插件）
  static Future<Uint8List?> squareThumb(Uint8List raw, {int size = 256}) async {
    try {
      final codec = await ui.instantiateImageCodec(raw);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final side = (img.width < img.height ? img.width : img.height).toDouble();
      final src = Rect.fromLTWH(
        ((img.width - side) / 2).clamp(0, double.infinity),
        ((img.height - side) / 2).clamp(0, double.infinity),
        side,
        side,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        img,
        src,
        Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(size, size);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      out.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
