import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/local_notes.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 游客模式的本地存储回归测试：数据只在本机，行为要与云端一致
/// （置顶优先、软删除进回收站、可恢复、可彻底删除）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('游客新建笔记 → 立即可见，字段齐全', () async {
    final created = await LocalNotes.create(
        title: '第一篇', content: '本地内容', tags: ['a'], pinned: false);
    expect(created['id'], startsWith('local-'));
    expect(created['user_id'], 'guest');

    final list = await LocalNotes.fetchNotes();
    expect(list.length, 1);
    expect(list.first['title'], '第一篇');
    expect(list.first['tags'], ['a']);
    expect(list.first['deleted_at'], isNull);
  });

  test('置顶优先，其余按更新时间倒序', () async {
    final a = await LocalNotes.create(title: 'A', content: '');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await LocalNotes.create(title: 'B', content: '');
    await LocalNotes.update(
        id: a['id'] as String, title: 'A', content: '', pinned: true);

    final list = await LocalNotes.fetchNotes();
    expect(list.length, 2);
    expect(list.first['title'], 'A'); // 置顶排最前
    expect(list[1]['title'], 'B');    // 未置顶的按时间倒序
  });

  test('删除进回收站 → 恢复 → 永久删除', () async {
    final n = await LocalNotes.create(title: '待删', content: '');
    final id = n['id'] as String;

    await LocalNotes.setDeleted(id, DateTime.now().toUtc().toIso8601String());
    expect((await LocalNotes.fetchNotes()).length, 0);
    expect((await LocalNotes.fetchTrash()).length, 1);

    await LocalNotes.setDeleted(id, null);
    expect((await LocalNotes.fetchNotes()).length, 1);
    expect((await LocalNotes.fetchTrash()).length, 0);

    await LocalNotes.purge(id);
    expect(await LocalNotes.count(), 0);
  });

  test('update 会写入新内容、标签与置顶状态', () async {
    final n = await LocalNotes.create(title: '旧', content: 'old');
    await LocalNotes.update(
        id: n['id'] as String,
        title: '新',
        content: 'new',
        tags: ['x'],
        pinned: true);

    final list = await LocalNotes.fetchNotes();
    expect(list.first['title'], '新');
    expect(list.first['content'], 'new');
    expect(list.first['tags'], ['x']);
    expect(list.first['pinned'], true);
  });

  test('连续新建：id 唯一（回归）', () async {
    for (var i = 0; i < 20; i++) {
      await LocalNotes.create(title: 'N$i', content: '');
    }
    final list = await LocalNotes.fetchNotes();
    expect(list.length, 20);
    expect(list.map((n) => n['id']).toSet().length, 20);
  });

  test('本地数据损坏时不崩，按空库处理', () async {
    SharedPreferences.setMockInitialValues({'guest_notes_v1': '这不是 JSON'});
    expect((await LocalNotes.fetchNotes()).length, 0);
    expect((await LocalNotes.fetchTrash()).length, 0);
  });
}

