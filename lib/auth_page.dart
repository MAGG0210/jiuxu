import 'package:flutter/material.dart';
import 'note_service.dart';
import 'app_theme.dart';

/// 登录页：吸血鬼风格
/// 血月当空、蝙蝠掠影、暗红哥特 —— 与「久序 / 加冕」的血色体系一脉相承。
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

// 吸血鬼调色板
const Color _blood = Color(0xFF8B0000); // 暗血
const Color _bloodBright = Color(0xFFE53935); // 鲜红
const Color _bloodDeep = Color(0xFF3A0808); // 干涸血
const Color _gold = Color(0xFFFFD54F); // 王冠金
const Color _ink = Color(0xFF0A0202); // 夜黑

class _AuthPageState extends State<AuthPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = '请输入邮箱和密码');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (_isLogin) {
        await NoteService.instance.signIn(email, pass);
      } else {
        await NoteService.instance.signUp(email, pass);
        // 若 Supabase 开了邮箱确认，会提示；这里按已注册处理
        if (mounted) {
          setState(() {
            _error = '注册成功，请登录（若开启邮箱验证请先验证邮箱）';
            _isLogin = true;
            _loading = false;
          });
        }
        return;
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _friendlyError(e);
        });
      }
    }
  }

  /// 把 Supabase 的英文异常翻译成用户能看懂的中文提示
  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('Invalid login credentials')) return '邮箱或密码错误';
    if (s.contains('already registered')) return '该邮箱已注册，请直接登录';
    if (s.contains('Email not confirmed') || s.contains('email_not_confirmed')) {
      return '邮箱尚未验证：请到邮箱点击确认链接后再登录';
    }
    if (s.contains('email_address_invalid')) return '邮箱地址无效，请使用真实邮箱';
    if (s.contains('Password should be at least')) return '密码太短（至少 6 位）';
    if (s.contains('rate limit') || s.contains('over_email_send_rate_limit')) {
      return '操作过于频繁，请稍后再试';
    }
    if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection') ||
        s.contains('TimeoutException')) {
      return '网络连接失败，请检查网络后重试';
    }
    return '操作失败：$s';
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '请先输入邮箱');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await NoteService.instance.resetPassword(email);
      if (mounted) {
        setState(() => _loading = false);
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: const Color(0xFF140606),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: _blood.withValues(alpha: 0.6)),
            ),
            title: const Text('血书已送出',
                style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
            content: const Text('请前往邮箱查收重置邮件，按邮件提示完成密码重置。',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  style: TextButton.styleFrom(foregroundColor: _bloodBright),
                  child: const Text('知道了')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '发送失败: $e';
        });
      }
    }
  }

  /// 游客模式：不登录、不联网，笔记只存本机
  Future<void> _enterGuest() async {
    await NoteService.instance.enterGuestMode();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ink,
      body: Stack(
        children: [
          _bloodBackdrop(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCard(),
                      const SizedBox(height: 18),
                      Text(
                        '无人扶我青云志 我自踏雪至山巅',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.28),
                          fontSize: 12,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 背景：血月 + 蝙蝠掠影 + 血色暗角
  Widget _bloodBackdrop() {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A0505), Color(0xFF0A0202)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: [
              // 血月
              Positioned(
                top: -60,
                right: -40,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _bloodBright.withValues(alpha: 0.45),
                        _blood.withValues(alpha: 0.16),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.5, 1],
                    ),
                  ),
                ),
              ),
              // 左下血色辉光
              Positioned(
                bottom: -80,
                left: -60,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _blood.withValues(alpha: 0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // 蝙蝠群
              const Positioned(
                  top: 54,
                  left: 26,
                  child: CustomPaint(
                      size: Size(48, 26), painter: _BatPainter(alpha: 0.55))),
              const Positioned(
                  top: 26,
                  left: 104,
                  child: CustomPaint(
                      size: Size(30, 16), painter: _BatPainter(alpha: 0.35))),
              const Positioned(
                  top: 118,
                  right: 44,
                  child: CustomPaint(
                      size: Size(38, 20), painter: _BatPainter(alpha: 0.45))),
              const Positioned(
                  top: 96,
                  left: 46,
                  child: CustomPaint(
                      size: Size(22, 12), painter: _BatPainter(alpha: 0.25))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF140606).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _blood.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: _blood.withValues(alpha: 0.32),
            blurRadius: 48,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 王冠 + 品牌
          const Icon(Icons.workspace_premium, color: _bloodBright, size: 44),
          const SizedBox(height: 10),
          Center(
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                colors: [_gold, _bloodBright],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ).createShader(r),
              child: const Text(
                '久序',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 10,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              _isLogin ? '血月当空 · 王座虚位以待' : '以血为契 · 刻下你的名讳',
              style: TextStyle(
                color: _bloodBright.withValues(alpha: 0.75),
                fontSize: 12.5,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 26),
          _bloodField(
            controller: _emailCtrl,
            label: '邮箱',
            icon: Icons.alternate_email,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _bloodField(
            controller: _passCtrl,
            label: '密码',
            icon: Icons.lock_outline,
            obscure: true,
          ),
          if (_isLogin)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loading ? null : _forgotPassword,
                style: TextButton.styleFrom(foregroundColor: _bloodBright),
                child: const Text('忘记密码？', style: TextStyle(fontSize: 13)),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _bloodBright.withValues(alpha: 0.95), fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
          GradientButton(
            loading: _loading,
            onPressed: _submit,
            gradient: const LinearGradient(
              colors: [_blood, _bloodBright],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            child: Text(
              _isLogin ? '登 录' : '注 册',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 4),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() {
              _isLogin = !_isLogin;
              _error = null;
            }),
            style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.6)),
            child: Text(_isLogin ? '没有账号？去注册' : '已有账号？去登录',
                style: const TextStyle(fontSize: 13)),
          ),
          Divider(color: _blood.withValues(alpha: 0.4), height: 20),
          TextButton.icon(
            onPressed: _loading ? null : _enterGuest,
            style: TextButton.styleFrom(
              foregroundColor: _gold.withValues(alpha: 0.85),
            ),
            icon: const Icon(Icons.person_outline, size: 18),
            label: const Text('游客登录（仅本地保存）'),
          ),
          const SizedBox(height: 2),
          Text(
            '游客模式不支持云备份与加冕签到',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  /// 血色输入框：暗底、干涸血描边、聚焦时鲜红发光
  Widget _bloodField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      cursorColor: _bloodBright,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _bloodBright.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: _bloodBright.withValues(alpha: 0.8)),
        filled: true,
        fillColor: const Color(0xFF1E0808),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _bloodDeep),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _blood.withValues(alpha: 0.55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _bloodBright, width: 1.6),
        ),
      ),
    );
  }
}

/// 蝙蝠剪影
class _BatPainter extends CustomPainter {
  final double alpha;
  const _BatPainter({this.alpha = 0.5});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2E0707).withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.50, h * 0.36)
      ..quadraticBezierTo(w * 0.30, h * 0.00, w * 0.00, h * 0.30)
      ..quadraticBezierTo(w * 0.16, h * 0.26, w * 0.20, h * 0.58)
      ..quadraticBezierTo(w * 0.31, h * 0.44, w * 0.50, h * 0.74)
      ..quadraticBezierTo(w * 0.69, h * 0.44, w * 0.80, h * 0.58)
      ..quadraticBezierTo(w * 0.84, h * 0.26, w * 1.00, h * 0.30)
      ..quadraticBezierTo(w * 0.70, h * 0.00, w * 0.50, h * 0.36)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BatPainter old) => old.alpha != alpha;
}
