import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'note_service.dart';

/// 加冕签到系统：血红色主题，累计签到天数（存 Supabase 跨端同步），
/// 逐级晋升，365 天加冕为王。
class CoronationPage extends StatefulWidget {
  const CoronationPage({super.key});

  @override
  State<CoronationPage> createState() => _CoronationPageState();
}

class _CoronationPageState extends State<CoronationPage> {
  static const Color bloodRed = Color(0xFFC62828);
  static const Color gold = Color(0xFFFFD54F);

  /// 等级体系：(所需天数, 称号)
  static const List<(int, String)> ranks = [
    (0, '乞丐'),
    (3, '男爵'),
    (7, '子爵'),
    (14, '伯爵'),
    (28, '侯爵'),
    (48, '公爵'),
    (90, '亲王'),
    (180, '大公'),
    (365, '王'),
  ];

  int _days = 0;
  String? _lastDate; // 最后签到日期 yyyy-MM-dd（服务端按 Asia/Shanghai 计算）
  bool _loading = true;
  String? _error;
  RealtimeChannel? _channel;

  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  bool get _checkedToday => _lastDate == _todayStr;

  String get _rank {
    String r = '乞丐';
    for (final (t, name) in ranks) {
      if (_days >= t) r = name;
    }
    return r;
  }

  bool get _isKing => _days >= 365;

  (int, String)? get _nextRank {
    for (final (t, name) in ranks) {
      if (_days < t) return (t, name);
    }
    return null;
  }

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
    // 游客模式没有云端签到数据，直接展示引导页
    if (NoteService.isGuest) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
      return;
    }
    try {
      final c = await NoteService.instance.fetchCheckin();
      if (mounted) {
        setState(() {
          _days = (c?['days'] as num?)?.toInt() ?? 0;
          _lastDate = c?['last_checkin']?.toString();
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载失败：${_friendlyError(e)}';
        });
      }
    }
  }

  void _subscribe() {
    _channel = NoteService.instance.subscribeCheckins(
      forUserId: NoteService.instance.userId,
      onChanged: _load,
    );
  }

  Future<void> _checkIn() async {
    if (NoteService.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('游客模式不支持加冕签到，请先登录')),
      );
      return;
    }
    if (_checkedToday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('今日已签到，明日再来')),
      );
      return;
    }
    final oldRank = _rank;
    try {
      final res = await NoteService.instance.checkIn();
      if (!mounted) return;
      setState(() {
        _days = (res['days'] as num?)?.toInt() ?? _days;
        _lastDate = res['last_checkin']?.toString();
      });
      if (_rank != oldRank) {
        _showPromotionDialog(oldRank);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('签到成功 · 已签到 $_days 天')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('签到失败：${_friendlyError(e)}')),
        );
      }
    }
  }

  /// 把底层异常翻译成用户能看懂的中文
  static String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('not authenticated') ||
        s.contains('JWT') ||
        s.contains('invalid claim')) {
      return '登录状态已失效，请重新登录后再签到';
    }
    if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('TimeoutException') ||
        s.contains('ClientException') ||
        s.contains('Connection')) {
      return '网络连接失败，请检查网络后重试';
    }
    if (s.contains('permission denied') || s.contains('row-level security')) {
      return '没有权限，请确认已登录';
    }
    return s;
  }

  /// 游客模式：签到要靠云端账号累计天数，这里只给引导
  Widget _buildGuestView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium,
                color: Colors.white24, size: 76),
            const SizedBox(height: 18),
            const Text('游客模式无法加冕',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2)),
            const SizedBox(height: 10),
            const Text(
              '加冕签到要把天数存在云端才能跨端累计。\n登录后即可开始你的加冕之路。',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white54, fontSize: 13, height: 1.7),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: bloodRed, foregroundColor: Colors.white),
              onPressed: () => NoteService.instance.exitGuestMode(),
              child: const Text('去登录 / 注册'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPromotionDialog(String oldRank) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF2A0A0A),
        title: const Icon(Icons.workspace_premium, color: gold, size: 56),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('晋升成功！',
                style: TextStyle(
                    color: gold, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('恭喜你从「$oldRank」加冕为「$_rank」',
                style: const TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: bloodRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c),
            child: const Text('继续加冕'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final next = _nextRank;
    final progress = next == null ? 1.0 : _days / next.$1;
    return Scaffold(
      backgroundColor: const Color(0xFF1A0606),
      body: _buildBody(next, progress),
    );
  }

  Widget _buildBody((int, String)? next, double progress) {
    if (NoteService.isGuest) {
      return _buildGuestView();
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: bloodRed));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: bloodRed, foregroundColor: Colors.white),
              onPressed: _load,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3A0D0D), Color(0xFF1A0606)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            children: [
              // 顶部：王冠 + 当前称号
              const Icon(Icons.workspace_premium, color: gold, size: 64),
              const SizedBox(height: 10),
              Text(
                _isKing ? '加冕成王' : '加冕之路',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    letterSpacing: 6),
              ),
              const SizedBox(height: 8),
              Text(_rank,
                  style: const TextStyle(
                      color: gold,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4)),
              const SizedBox(height: 6),
              Text(
                _isKing
                    ? '吾王加冕，万民臣服'
                    : '已签到 $_days 天 · ${next == null ? '已达巅峰' : '距「${next.$2}」还差 ${next.$1 - _days} 天'}',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 28),
              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: Colors.white12,
                  color: bloodRed,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                next == null
                    ? '加冕进度 100%'
                    : '晋升进度 ${(_days * 100 / next.$1).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 32),
              // 签到按钮（血红色）
              _buildCheckInButton(),
              const SizedBox(height: 36),
              // 等级谱系
              _buildRankTable(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInButton() {
    final done = _checkedToday;
    return InkWell(
      onTap: _checkIn,
      borderRadius: BorderRadius.circular(60),
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: done
              ? const LinearGradient(
                  colors: [Color(0xFF5A2A2A), Color(0xFF3A1A1A)])
              : const LinearGradient(
                  colors: [Color(0xFFE53935), Color(0xFF8B0000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
          boxShadow: done
              ? const []
              : [
                  BoxShadow(
                    color: bloodRed.withValues(alpha: 0.55),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                  const BoxShadow(
                      color: Color(0x33FF5252),
                      blurRadius: 60,
                      spreadRadius: 10),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(done ? Icons.check_circle : Icons.touch_app,
                color: done ? Colors.white38 : Colors.white, size: 40),
            const SizedBox(height: 6),
            Text(
              done ? '今日已加冕' : '点击加冕',
              style: TextStyle(
                  color: done ? Colors.white38 : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankTable() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('加冕谱系',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...ranks.map(_buildRankRow),
        ],
      ),
    );
  }

  Widget _buildRankRow((int, String) rank) {
    final (t, name) = rank;
    final achieved = _days >= t;
    final current = _rank == name;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            achieved
                ? (name == '王'
                    ? Icons.workspace_premium
                    : Icons.verified)
                : Icons.lock_outline,
            size: 18,
            color: achieved
                ? (name == '王' ? gold : Colors.white70)
                : Colors.white24,
          ),
          const SizedBox(width: 10),
          Text(name,
              style: TextStyle(
                  color: achieved ? Colors.white : Colors.white38,
                  fontSize: 15,
                  fontWeight:
                      current ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          Text('$t 天',
              style: TextStyle(
                  color: achieved
                      ? (name == '王' ? gold : Colors.white54)
                      : Colors.white24,
                  fontSize: 13)),
          if (current)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: bloodRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('当前',
                  style: TextStyle(fontSize: 11, color: Colors.white)),
            ),
        ],
      ),
    );
  }
}

