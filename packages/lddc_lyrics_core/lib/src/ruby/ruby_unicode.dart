import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Ruby 注音链路的 Unicode 归一化入口。
///
/// Python 版使用 `unicodedata.normalize("NFKC", ...)`，这里必须使用完整
/// NFKC，不能只维护少量全角字符替换，否则半角片假名、兼容数字和组合字符
/// 会在索引映射阶段和 Python 基线分叉。
String normalizeRubyNfkc(String input) =>
    input.isEmpty ? input : unorm.nfkc(input);
