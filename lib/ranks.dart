/// 王室等级体系 —— 加冕签到、头衔展示、聊天室卡片共用同一份定义。
///
/// (所需天数, 称号)
const List<(int, String)> royalRanks = [
  (0, '乞丐'),
  (3, '男爵'),
  (7, '子爵'),
  (14, '伯爵'),
  (28, '侯爵'),
  (48, '公爵'),
  (90, '亲王'),
  (180, '大公'),
  (365, '王'),
];

/// 按累计天数取称号
String rankOf(int days) {
  var name = royalRanks.first.$2;
  for (final (t, n) in royalRanks) {
    if (days >= t) name = n;
  }
  return name;
}

/// 下一个头衔：(所需天数, 称号)，已封王则返回 null
(int, String)? nextRankOf(int days) {
  for (final (t, n) in royalRanks) {
    if (days < t) return (t, n);
  }
  return null;
}

/// 距下一个头衔还差几天（已封王返回 0）
int daysToNextRank(int days) {
  final next = nextRankOf(days);
  return next == null ? 0 : next.$1 - days;
}

