import 'package:flutter/material.dart';
import 'note_service.dart';
import 'app_theme.dart';

/// 账户管理：查看邮箱、修改密码。
/// 游客模式没有账号 —— 这里改为引导登录（登录后才有云备份与签到）。
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _newPassCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final newPass = _newPassCtrl.text;
    final confirm = _confirmCtrl.text;
    if (newPass.length < 6) {
      setState(() { _error = '密码至少 6 位'; _success = null; });
      return;
    }
    if (newPass != confirm) {
      setState(() { _error = '两次输入的密码不一致'; _success = null; });
      return;
    }
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      await NoteService.instance.updatePassword(newPass);
      if (mounted) {
        _newPassCtrl.clear();
        _confirmCtrl.clear();
        setState(() {
          _loading = false;
          _success = '密码修改成功';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '修改失败: $e';
        });
      }
    }
  }

  /// 游客模式：没有账号可管，给一个清晰的登录入口
  Widget _buildGuestView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: AppColors.gradientSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text('当前为游客模式',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(
              '笔记只保存在本机，未开启云备份。\n登录后可获得：跨端实时同步、加冕签到、修改密码。\n本地笔记不会自动上传（可用列表里的「导出/分享」备份）。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.7,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            GradientButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                await NoteService.instance.exitGuestMode();
                nav.pop();
              },
              child: const Text('去登录 / 注册',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (NoteService.isGuest) {
      return Scaffold(
        appBar: AppBar(title: const Text('账户')),
        body: _buildGuestView(context),
      );
    }
    final email = NoteService.instance.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('账户')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.alternate_email),
              title: const Text('登录邮箱'),
              subtitle: Text(email),
            ),
          ),
          const SizedBox(height: 24),
          const Text('修改密码',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: _newPassCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '新密码（至少 6 位）',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '确认新密码',
              prefixIcon: Icon(Icons.lock_reset),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Colors.red.shade400)),
          if (_success != null)
            Text(_success!, style: TextStyle(color: Colors.green.shade600)),
          const SizedBox(height: 16),
          GradientButton(
            loading: _loading,
            onPressed: _changePassword,
            child: const Text('确认修改',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
