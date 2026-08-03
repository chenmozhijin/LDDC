/// 统一缓存 TTL 策略常量（按Python版链路习惯值）。
class CacheTtl {
  CacheTtl._();

  /// 搜索/翻译/歌词：4 小时。
  static const Duration search = Duration(hours: 4);
  static const Duration translate = Duration(hours: 4);
  static const Duration lyrics = Duration(hours: 4);

  /// KG dfid：30 分钟。
  static const Duration kgDfid = Duration(minutes: 30);

  /// NE匿名态：10 天（可由服务端过期时间进一步收紧）。
  static const Duration neteaseAnonymous = Duration(days: 10);
}
