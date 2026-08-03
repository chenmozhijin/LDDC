/// 应用级元数据。
///
/// 版本号会被 About 页、桌面服务信息和歌词导出注释共同使用，因此不能放在
/// converter 模块里；否则只想显示版本号的页面也会被迫依赖歌词转换实现。
const String kLddcVersion = 'v0.10.0-alpha.1';
