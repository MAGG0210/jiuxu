import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_page.dart';
import 'app_theme.dart';
import 'chat_page.dart';
import 'community_page.dart';
import 'habit_page.dart';
import 'login_dialog.dart';
import 'note_service.dart';
import 'notes_page.dart';
import 'pomodoro_page.dart';
import 'profile_store.dart';
import 'royal_page.dart';
import 'settings_page.dart';
import 'theme_store.dart';
import 'todo_page.dart';
import 'trash_page.dart';

const Color _blood = Color(0xFF8B0000);
const Color _bloodBright = Color(0xFFE53935);
const Color _gold = Color(0xFFFFD54F);

/// 主壳：
/// - 底部 4 tab：笔记 / 待办 / 打卡 / 聊天室
/// - 左上角头像：未登录 → 弹登录入口；已登录 → 从左侧滑出侧边栏
/// - 右上角：王室头衔系统入口（独立页面，不受侧边栏控制）
class HomeShell extends StatefulWidget {
  final int initialIndex;
  const HomeShell({super.key, this.initialIndex = 0});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialIndex;

  /// 用 GlobalKey 直接控制抽屉 —— `Scaffold.of(context)` 在本 State 的 context 上
  /// 拿到的是 Scaffold 之上的 context，会抛异常导致点击无反应。
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 底部 tab 顺序固定：笔记 / 待办 / 打卡 / 聊天室 / 社区
  static const List<String> _titles = ['久序', '待办', '打卡', '聊天室', '社区'];

  bool get _loggedIn => Supabase.instance.client.auth.currentSession != null;

  @override
  void initState() {
    super.initState();
    // 登录状态：进主界面时拉一次云端资料（昵称 / 头像 / 头衔天数）
    if (_loggedIn) {
      ProfileStore.pullFromCloud().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听登录状态：登录/登出后左上角（「登录」文字 ↔ 头像）与侧边栏自动刷新
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) => _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 54,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true, // 页面标题居中：【左上角 登录/头像】与【右上角王室图标】之间
        leadingWidth: _loggedIn ? 64 : 86,
        leading: Center(
          child: _loggedIn
              ? _avatarEntry()
              : TextButton(
                  onPressed: _onAvatarTap,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('登录',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                ),
        ),
        title: Text(
          _titles[_index],
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 2),
        ),
        actions: [
          IconButton(
            tooltip: '王室头衔',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const RoyalPage()),
            ),
            icon: const Icon(Icons.workspace_premium, color: _bloodBright),
          ),
          const SizedBox(width: 6),
        ],
      ),
      drawer: _buildDrawer(),
      body: IndexedStack(
        index: _index,
        children: const [
          NotesPage(),
          TodoPage(),
          HabitPage(),
          ChatPage(),
          CommunityPage(),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  /// 头像 / 左上角「登录」文字：**一律打开侧边栏**
  /// （登录入口在侧边栏顶部；游客也能正常打开侧边栏看自己的信息）
  void _onAvatarTap() {
    _scaffoldKey.currentState?.openDrawer();
  }

  // ---------- 左上角头像 ----------
  Widget _avatarEntry() {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: _onAvatarTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: ProfileStore.profile,
          builder: (context, _, __) => UserAvatar(
            size: 36,
            loggedIn: _loggedIn,
            onTap: _onAvatarTap,
          ),
        ),
      ),
    );
  }

  // ---------- 侧边栏 ----------
  Widget _buildDrawer() {
    return Drawer(
      child: ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: ProfileStore.profile,
        builder: (context, _, __) {
          final nickname = _loggedIn ? ProfileStore.nickname : '游客';
          final title = _loggedIn ? ProfileStore.title : '未加冕';
          final days = int.tryParse('${ProfileStore.profile.value['days'] ?? 0}') ?? 0;

          return Column(
            children: [
              // 用户信息区
              DrawerHeader(
                margin: EdgeInsets.zero,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF3A0D0D), Color(0xFF1A0606)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        UserAvatar(size: 58, loggedIn: _loggedIn),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: InkWell(
                            onTap: _changeAvatar,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: _bloodBright,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.photo_camera,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                      colors: [_blood, _bloodBright]),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(title,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 6),
                              Text('$days 天',
                                  style: TextStyle(
                                      color: _gold.withValues(alpha: 0.9),
                                      fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _loggedIn
                                ? (NoteService.instance.email ?? '')
                                : '游客模式 · 数据只存本机',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 侧边栏最顶部：登录入口（游客 / 未登录时）
              if (!_loggedIn)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SizedBox(
                    height: 46,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _blood,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        showLoginDialog(context);
                      },
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('登录 / 注册',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),

              // 菜单
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('番茄钟'),
                subtitle: const Text('25 分钟专注，专注完自动提醒休息'),
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute(
                      builder: (_) => const PomodoroPage()));
                },
              ),
              const Divider(height: 8),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('修改昵称'),
                onTap: () {
                  Navigator.pop(context);
                  _changeNickname();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('修改头像'),
                onTap: () {
                  Navigator.pop(context);
                  _changeAvatar();
                },
              ),
              if (_loggedIn)
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('修改密码'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push<void>(context,
                        MaterialPageRoute(builder: (_) => const AccountPage()));
                  },
                ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push<void>(context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('回收站'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push<void>(context,
                      MaterialPageRoute(builder: (_) => const TrashPage()));
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('外观'),
                subtitle: Text(switch (ThemeStore.current) {
                  ThemeMode.light => '亮色',
                  ThemeMode.dark => '暗色',
                  ThemeMode.system => '跟随系统',
                }),
                onTap: () {
                  final next = switch (ThemeStore.current) {
                    ThemeMode.system => ThemeMode.light,
                    ThemeMode.light => ThemeMode.dark,
                    ThemeMode.dark => ThemeMode.system,
                  };
                  ThemeStore.set(next);
                  Navigator.pop(context);
                },
              ),

              const Spacer(),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                    _loggedIn ? Icons.logout : Icons.person_off_outlined,
                    color: _bloodBright),
                title: Text(_loggedIn ? '退出登录' : '退出游客模式'),
                onTap: () async {
                  final nav = Navigator.of(context);
                  if (_loggedIn || NoteService.isGuest) {
                    await NoteService.instance.signOut();
                    nav.pop();
                  } else {
                    nav.pop();
                    showLoginDialog(context);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  /// 改昵称：本机立即生效；已登录且开了云同步则同步到云端
  /// （聊天室 / 社区的消息卡片会跟着显示新昵称）
  Future<void> _changeNickname() async {
    final ctrl = TextEditingController(text: ProfileStore.nickname);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 16,
          decoration: const InputDecoration(
            labelText: '昵称',
            hintText: '别人在聊天室 / 社区看到的名字',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) {
      ctrl.dispose();
      return;
    }
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (name.isEmpty) return;
    await ProfileStore.updateLocal(nickname: name);
    if (_loggedIn && ProfileStore.settings.value['cloudSync'] == true) {
      try {
        await ProfileStore.pushToCloud();
      } catch (_) {/* 云端失败不影响本机 */}
    }
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('昵称已更新')));
    }
  }

  /// 改头像：选图 → 居中裁成方图 → 本地保存 → （已登录且开了云同步）上传云端
  Future<void> _changeAvatar() async {
    if (!_loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登录后才能设置云端头像（游客只存本机）')));
    }
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (picked == null) return;
      final raw = await picked.readAsBytes();
      final thumb = await ProfileStore.squareThumb(raw, size: 256);
      if (thumb == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('这张图没法处理，换一张试试')));
        }
        return;
      }
      await ProfileStore.updateLocal(avatarBytes: thumb);
      if (_loggedIn && ProfileStore.settings.value['cloudSync'] == true) {
        await ProfileStore.pushToCloud(avatarBytes: thumb);
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('头像已更新')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('设置头像失败：$e')));
      }
    }
  }

  // ---------- 底部 4 tab ----------
  Widget _buildBottomBar() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(
            top: BorderSide(color: dark ? Colors.white12 : Colors.black12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.4 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.notes_rounded, '笔记'),
              _navItem(1, Icons.checklist_rounded, '待办'),
              _navItem(2, Icons.event_available_rounded, '打卡'),
              _navItem(3, Icons.forum_rounded, '聊天室'),
              _navItem(4, Icons.grid_view_rounded, '社区'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _index == index;
    final color =
        selected ? AppColors.primary : Colors.grey.withValues(alpha: 0.7);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _index = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

/// 圆形头像：网络图 → 本地裁剪图 → 灰色默认人像（未登录）
class UserAvatar extends StatelessWidget {
  final double size;
  final bool loggedIn;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    this.size = 36,
    this.loggedIn = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final img = ProfileStore.avatarImage;
    Widget content;
    if (!loggedIn && img == null) {
      // 未登录：灰色默认头像
      content = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.person,
            size: size * 0.6, color: Colors.grey.shade600),
      );
    } else if (img == null) {
      content = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_blood, _bloodBright]),
          shape: BoxShape.circle,
        ),
        child: Text(
          ProfileStore.nickname.characters.first,
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700),
        ),
      );
    } else {
      content = ClipOval(
        child: Image(
          image: img,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            color: Colors.grey.withValues(alpha: 0.35),
            child: Icon(Icons.person,
                size: size * 0.6, color: Colors.grey.shade600),
          ),
        ),
      );
    }
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}
