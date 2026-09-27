import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'note_service.dart';
import 'profile_store.dart';
import 'ranks.dart';

const Color _blood = Color(0xFF8B0000);
const Color _bloodBright = Color(0xFFE53935);
const Color _gold = Color(0xFFFFD54F);

/// 王室头衔系统（右上角入口）。
///
/// 展示当前头衔、累计天数、晋升进度与完整谱系；头衔数据与云端 `checkins`
/// 联动，聊天室与侧边栏读同一份数据。
class RoyalPage extends StatefulWidget {
  const RoyalPage({super.key});

  @override
  State<RoyalPage> createState() => _RoyalPageState();
}

class _RoyalPageState extends State<RoyalPage> {
  int _days = 0;
  bool _loading = true;
  String? _error;

  bool get _loggedIn => Supabase.instance.client.auth.currentSession != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 游客模式或未登录：用本机记录的天数（双保险：只要数据层认为是游客，
    // 就绝不调云端签到接口）
    if (NoteService.isGuest || !_loggedIn) {
      final localDays = int.tryParse('${ProfileStore.profile.value['days'] ?? 0}') ?? 0;
      setState(() {
        _days = localDays;
        _loading = false;
      });
      return;
    }
    try {
      final c = await NoteService.instance.fetchCheckin();
      final days = (c?['days'] as num?)?.toInt() ?? 0;
      // 顺手把天数与头衔写回资料（聊天室要读）
      await ProfileStore.updateLocal(days: days, title: rankOf(days));
      if (mounted) {
        setState(() {
          _days = days;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0606),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3A0D0D), Color(0xFF1A0606)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _bloodBright));
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
                  backgroundColor: _blood, foregroundColor: Colors.white),
              onPressed: _load,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final rank = rankOf(_days);
    final next = nextRankOf(_days);
    final progress = next == null ? 1.0 : _days / next.$1;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
              ),
              const Spacer(),
              const Text('王室头衔',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 15, letterSpacing: 4)),
              const Spacer(),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 12),
          const Icon(Icons.workspace_premium, color: _bloodBright, size: 64),
          const SizedBox(height: 12),
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              colors: [_gold, Color(0xFFFF8A65)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(r),
            child: Text(rank,
                style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    color: Colors.white)),
          ),
          const SizedBox(height: 6),
          Text(
            _loggedIn
                ? '已签到 $_days 天'
                : '未登录 · 仅本机记录 $_days 天',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          if (!_loggedIn) ...[
            const SizedBox(height: 12),
            Text('登录后头衔会云端同步，聊天室里也会显示',
                style: TextStyle(
                    color: _gold.withValues(alpha: 0.8), fontSize: 12.5)),
          ],
          const SizedBox(height: 26),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.white12,
              color: _bloodBright,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            next == null
                ? '已登王座 · 加冕圆满'
                : '距「${next.$2}」还差 ${daysToNextRank(_days)} 天',
            style: const TextStyle(color: Colors.white38, fontSize: 12.5),
          ),
          const SizedBox(height: 28),
          Container(
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
                const Text('王室谱系',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...royalRanks.map((r) {
                  final (t, name) = r;
                  final achieved = _days >= t;
                  final current = rank == name;
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
                              ? (name == '王' ? _gold : Colors.white70)
                              : Colors.white24,
                        ),
                        const SizedBox(width: 10),
                        Text(name,
                            style: TextStyle(
                                color:
                                    achieved ? Colors.white : Colors.white38,
                                fontSize: 15,
                                fontWeight: current
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        const Spacer(),
                        Text('$t 天',
                            style: TextStyle(
                                color: achieved
                                    ? (name == '王' ? _gold : Colors.white54)
                                    : Colors.white24,
                                fontSize: 13)),
                        if (current)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _bloodBright,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('当前',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white)),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


