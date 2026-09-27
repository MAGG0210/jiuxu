import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/todo_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 待办数据层回归测试：排序、完成、到点提醒判定、持久化。
void main() {
  setUp(() {
    // 预置过示例数据（真实场景由首次 load 写入），避免干扰其余用例的计数断言
    SharedPreferences.setMockInitialValues({'todos_seeded_v1': true});
    TodoStore.notifier.value = <Map<String, dynamic>>[];
  });

  test('首次使用预置 3 条示例待办：妈妈生日 / 爸爸生日 / 过年时间', () async {
    SharedPreferences.setMockInitialValues({}); // 全新安装：没有 seed 标记
    TodoStore.notifier.value = <Map<String, dynamic>>[];
    await TodoStore.load();

    final titles = TodoStore.todos.map((t) => t['title']).toList();
    expect(titles, containsAll(['妈妈生日', '爸爸生日', '过年时间']));
    // 过年时间带提醒，生日留给用户自己填
    final spring = TodoStore.todos.firstWhere((t) => t['title'] == '过年时间');
    expect(spring['remind_at'], isNotNull);
  });

  test('新建待办 → 出现在清单，默认未完成', () async {
    await TodoStore.add(title: '写周报');
    expect(TodoStore.todos.length, 1);
    expect(TodoStore.todos.first['title'], '写周报');
    expect(TodoStore.todos.first['done'], false);
    expect(TodoStore.pendingCount, 1);
  });

  test('排序：带提醒的按时间升序在前，无提醒的排最后', () async {
    await TodoStore.add(title: '无提醒');
    await TodoStore.add(
        title: '晚点', remindAt: DateTime.now().add(const Duration(hours: 5)));
    await TodoStore.add(
        title: '马上', remindAt: DateTime.now().add(const Duration(minutes: 10)));

    final titles = TodoStore.todos.map((t) => t['title']).toList();
    expect(titles, ['马上', '晚点', '无提醒']);
  });

  test('勾选完成后沉到末尾，取消后回到待办', () async {
    await TodoStore.add(title: 'A');
    await TodoStore.add(title: 'B');
    final idA = TodoStore.todos
        .firstWhere((t) => t['title'] == 'A')['id'] as String;

    await TodoStore.toggle(idA);
    expect(TodoStore.todos.last['title'], 'A');
    expect(TodoStore.pendingCount, 1);

    await TodoStore.toggle(idA);
    expect(TodoStore.pendingCount, 2);
  });

  test('到点判定：过期未提醒 → 命中；标记后不再重复', () async {
    await TodoStore.add(
        title: '吃药',
        remindAt: DateTime.now().subtract(const Duration(minutes: 1)));

    final due = TodoStore.dueNow();
    expect(due.length, 1);
    expect(due.first['title'], '吃药');

    await TodoStore.markNotified(due.first['id'] as String);
    expect(TodoStore.dueNow(), isEmpty);
  });

  test('未到点 / 已完成 都不触发提醒', () async {
    await TodoStore.add(
        title: '未来的事', remindAt: DateTime.now().add(const Duration(hours: 1)));
    expect(TodoStore.dueNow(), isEmpty);

    await TodoStore.add(
        title: '过期但已完成',
        remindAt: DateTime.now().subtract(const Duration(hours: 1)));
    final id = TodoStore.todos
        .firstWhere((t) => t['title'] == '过期但已完成')['id'] as String;
    await TodoStore.toggle(id);
    expect(TodoStore.dueNow(), isEmpty);
  });

  test('改提醒时间会重置提醒标记（能再次提醒）', () async {
    await TodoStore.add(
        title: 'X', remindAt: DateTime.now().subtract(const Duration(minutes: 1)));
    final id = TodoStore.todos.first['id'] as String;
    await TodoStore.markNotified(id);
    expect(TodoStore.dueNow(), isEmpty);

    await TodoStore.update(
        id: id, remindAt: DateTime.now().add(const Duration(minutes: 1)));
    expect(TodoStore.todos.first['notified'], false);
  });

  test('清除提醒时间', () async {
    await TodoStore.add(
        title: '有提醒', remindAt: DateTime.now().add(const Duration(hours: 3)));
    final id = TodoStore.todos.first['id'] as String;
    await TodoStore.update(id: id, clearRemind: true);
    expect(TodoStore.todos.first['remind_at'], isNull);
  });

  test('同一毫秒内连续新建：id 唯一，勾选只影响一条（回归）', () async {
    for (var i = 0; i < 20; i++) {
      await TodoStore.add(title: 'T$i');
    }
    final ids = TodoStore.todos.map((t) => t['id']).toSet();
    expect(ids.length, 20, reason: 'id 重复会让数据互相覆盖');

    await TodoStore.toggle(TodoStore.todos.first['id'] as String);
    final doneCount = TodoStore.todos.where((t) => t['done'] == true).length;
    expect(doneCount, 1, reason: 'id 撞了会让多条待办一起被勾选');
  });

  test('删除后清单为空', () async {
    await TodoStore.add(title: '临时的');
    await TodoStore.remove(TodoStore.todos.first['id'] as String);
    expect(TodoStore.todos, isEmpty);
  });

  test('持久化：重新 load 后数据还在', () async {
    await TodoStore.add(
        title: '持久化测试',
        remindAt: DateTime.now().add(const Duration(hours: 2)));
    TodoStore.notifier.value = <Map<String, dynamic>>[];
    await TodoStore.load();
    expect(TodoStore.todos.length, 1);
    expect(TodoStore.todos.first['title'], '持久化测试');
  });
}


