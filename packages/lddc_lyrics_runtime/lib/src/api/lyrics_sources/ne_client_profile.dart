/// NE云音乐桌面客户端协议身份。
///
/// EAPI 请求和图片 CDN 必须使用同一套已验证的客户端版本与 User-Agent。
/// 将这些字段集中在公共只读常量中，可以避免升级版本时只修改其中一条链路，
/// 导致接口请求正常但 `p1.music.126.net` 歌单封面被 CDN 拒绝。
abstract final class NeClientProfile {
  static const String desktopAppVersion = '3.1.3.203419';
  static const int mconfigVersion = 733184;
  static const String chromiumMajorVersion = '91';

  /// NE桌面客户端的完整标准 UA；字段顺序也是 CDN 身份判定的一部分。
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 '
      'NeteaseMusicDesktop/3.1.3.203419';
}
