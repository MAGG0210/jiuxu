import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/note_service.dart';

/// 回归测试：PostgREST 对 `RETURNS TABLE` 的 RPC 一律返回 JSON 数组
/// （即使只有一行），修复前 `Map<String, dynamic>.from(res)` 会抛 _TypeError。
void main() {
  group('签到 RPC 返回值归一', () {
    test('单行数组 → 取首行（修复前的崩溃场景）', () {
      final row = NoteService.normalizeRpcRow([
        {'days': 3, 'last_checkin': '2026-09-27'}
      ]);
      expect(row['days'], 3);
      expect(row['last_checkin'], '2026-09-27');
    });

    test('单对象形状（composite/scalar 函数）也能吃', () {
      final row = NoteService.normalizeRpcRow(
          {'days': 8, 'last_checkin': '2026-09-27'});
      expect(row['days'], 8);
      expect(row['last_checkin'], '2026-09-27');
    });

    test('多行数组只取第一行，不炸', () {
      final row = NoteService.normalizeRpcRow([
        {'days': 1, 'last_checkin': '2026-09-25'},
        {'days': 2, 'last_checkin': '2026-09-26'},
      ]);
      expect(row['days'], 1);
    });

    test('空数组 → 明确抛错，而不是静默返回错数据', () {
      expect(() => NoteService.normalizeRpcRow(<dynamic>[]), throwsStateError);
    });

    test('null / 非 Map → 明确抛错', () {
      expect(() => NoteService.normalizeRpcRow(null), throwsStateError);
      expect(() => NoteService.normalizeRpcRow('nope'), throwsStateError);
    });
  });
}
