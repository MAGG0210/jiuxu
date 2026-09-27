import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/ranks.dart';

/// 王室等级体系：头衔 / 下一级 / 还差几天（聊天室、侧边栏、王室页共用）
void main() {
  test('称号按累计天数递进', () {
    expect(rankOf(0), '乞丐');
    expect(rankOf(2), '乞丐');
    expect(rankOf(3), '男爵');
    expect(rankOf(6), '男爵');
    expect(rankOf(7), '子爵');
    expect(rankOf(364), '大公');
    expect(rankOf(365), '王');
    expect(rankOf(9999), '王');
  });

  test('下一级与差值', () {
    expect(nextRankOf(0)?.$2, '男爵');
    expect(nextRankOf(0)?.$1, 3);
    expect(daysToNextRank(0), 3);
    expect(daysToNextRank(2), 1);
    expect(daysToNextRank(3), 4); // 男爵 → 子爵(7)
    expect(nextRankOf(365), isNull);
    expect(daysToNextRank(365), 0);
  });

  test('谱系表是从 0 到 365 的升序', () {
    expect(royalRanks.first.$1, 0);
    expect(royalRanks.last.$1, 365);
    for (var i = 1; i < royalRanks.length; i++) {
      expect(royalRanks[i].$1, greaterThan(royalRanks[i - 1].$1));
    }
  });
}
