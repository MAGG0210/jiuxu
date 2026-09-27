import 'package:flutter/material.dart';

import 'note_service.dart';

const Color _blood = Color(0xFF8B0000);
const Color _bloodBright = Color(0xFFE53935);

/// 弹出登录弹窗（吸血鬼风格）。登录成功后自己关闭，页面自动切到主界面。
Future<void> showLoginDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const LoginDialog(),
  );
}

class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key});

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isLogin) {
        await NoteService.instance.signIn(email, pass);
        if (mounted) {
          Navigator.pop(context); // 登录成功：关掉弹窗，回到页面（会自动进主界面）
        }
        return;
      } else {
        await NoteService.instance.signUp(email, pass);
        if (mounted) {
          setState(() {
            _isLogin = true;
            _loading = false;
            _error = '注册成功，请登录（若开启邮箱验证请先验证邮箱）';
          });
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _friendly(e);
        });
      }
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('Invalid login credentials')) return '邮箱或密码错误';
    if (s.contains('already registered')) return '该邮箱已注册，请直接登录';
    if (s.contains('Email not confirmed') || s.contains('email_not_confirmed')) {
      return '邮箱尚未验证：请到邮箱点击确认链接后再登录';
    }
    if (s.contains('Password should be at least')) return '密码太短（至少 6 位）';
    if (s.contains('rate limit')) return '操作过于频繁，请稍后再试';
    if (s.contains('SocketException') ||
        s.contains('Connection') ||
        s.contains('TimeoutException')) {
      return '网络连接失败，请检查网络后重试';
    }
    return '操作失败：$s';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF140606),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _blood.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
                color: _blood.withValues(alpha: 0.3),
                blurRadius: 40,
                spreadRadius: 2),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部：标题 + 关闭按钮
              Row(
                children: [
                  const Icon(Icons.workspace_premium,
                      color: _bloodBright, size: 26),
                  const SizedBox(width: 8),
                  Text(_isLogin ? '登录久序' : '注册账号',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close,
                        color: Colors.white54, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _isLogin ? '血月当空 · 王座虚位以待' : '以血为契 · 刻下你的名讳',
                style: TextStyle(
                    color: _bloodBright.withValues(alpha: 0.75),
                    fontSize: 12,
                    letterSpacing: 2),
              ),
              const SizedBox(height: 18),
              _field(_emailCtrl, '邮箱', Icons.alternate_email,
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _field(_passCtrl, '密码', Icons.lock_outline, obscure: true),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _bloodBright.withValues(alpha: 0.95),
                        fontSize: 12.5)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _blood,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isLogin ? '登 录' : '注 册',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4)),
                ),
              ),
              const SizedBox(height: 4),
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
              Divider(color: _blood.withValues(alpha: 0.4), height: 16),
              Row(
                children: [
                  Icon(Icons.cloud_off,
                      size: 13, color: Colors.white.withValues(alpha: 0.35)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('也可以继续用游客模式：数据只存本机，不影响使用',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: 0.35))),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: ctrl,
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
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF3A0808)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: _blood.withValues(alpha: 0.55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: _bloodBright, width: 1.6),
        ),
      ),
    );
  }
}
