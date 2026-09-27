import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 番茄钟：25 分钟专注 + 5 分钟短休，每完成 4 个专注来一次 15 分钟长休。
/// 纯本机功能（今日完成数存本机），不依赖登录，随手可用。
class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key});

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  static const Color _gold = Color(0xFFFFD54F);
  static const Color _blood = Color(0xFFE53935);
  static const Color _bg = Color(0xFF1A0606);

  static const Map<String, int> _durations = {
    '专注': 25 * 60,
    '短休息': 5 * 60,
    '长休息': 15 * 60,
  };

  String _mode = '专注';
  int _left = 25 * 60;
  bool _running = false;
  int _doneToday = 0;
  int _focusInCycle = 0; // 本循环里已完成的专注数（每 4 个换长休）
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _todayKey {
    final n = DateTime.now();
    return 'pomodoro_${n.year}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadToday() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _doneToday = prefs.getInt(_todayKey) ?? 0);
  }

  Future<void> _bumpToday() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_todayKey) ?? 0) + 1;
    await prefs.setInt(_todayKey, next);
    if (mounted) setState(() => _doneToday = next);
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= 1) {
        _finish();
      } else {
        setState(() => _left--);
      }
    });
  }

  void _finish() {
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    final finished = _mode;
    if (finished == '专注') {
      _focusInCycle++;
      _bumpToday();
    }
    final next = finished == '专注'
        ? (_focusInCycle % 4 == 0 ? '长休息' : '短休息')
        : '专注';
    setState(() {
      _running = false;
      _mode = next;
      _left = _durations[next]!;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            finished == '专注' ? '专注完成，去休息一下 ☕' : '休息结束，回来继续 👑'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _left = _durations[_mode]!;
    });
  }

  void _switchMode(String mode) {
    _timer?.cancel();
    setState(() {
      _running = false;
      _mode = mode;
      _left = _durations[mode]!;
    });
  }

  String get _clock {
    final m = (_left ~/ 60).toString().padLeft(2, '0');
    final s = (_left % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total = _durations[_mode]!;
    final elapsed = total - _left;
    final progress = (elapsed / total).clamp(0.0, 1.0);
    final accent = _mode == '专注' ? _blood : _gold;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('番茄钟'),
        backgroundColor: Colors.transparent,
        foregroundColor: _gold,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            // 模式切换
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: _durations.keys
                    .map((m) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: SizedBox(
                                width: double.infinity,
                                child: Text(m,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _mode == m ? _bg : _gold,
                                      fontWeight: FontWeight.w600,
                                    )),
                              ),
                              selected: _mode == m,
                              selectedColor: _gold,
                              backgroundColor: Colors.transparent,
                              side: BorderSide(color: _gold.withValues(alpha: 0.5)),
                              onSelected: (_) => _switchMode(m),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const Spacer(),
            // 计时圆环
            SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    height: 240,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 10,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_clock,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            fontFeatures: [FontFeature.tabularFigures()],
                          )),
                      const SizedBox(height: 6),
                      Text(_mode,
                          style: TextStyle(
                            color: _running ? accent : Colors.white54,
                            fontSize: 15,
                            letterSpacing: 2,
                          )),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重置'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _gold,
                    side: BorderSide(color: _gold.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _toggle,
                  icon: Icon(_running ? Icons.pause : Icons.play_arrow, size: 20),
                  label: Text(_running ? '暂停' : '开始'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              '今日完成 $_doneToday 个番茄 🍅',
              style: TextStyle(color: _gold.withValues(alpha: 0.9), fontSize: 15),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                '25 分钟专注 + 5 分钟休息，每 4 个专注换一次 15 分钟长休息',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45), fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }
}


