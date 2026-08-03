/// 日文字符类型。
enum CharType {
  /// 日文汉字。
  kanji,

  /// 平假名。
  hiragana,

  /// 片假名。
  katakana,

  /// 标点与符号。
  symbol,

  /// 其他字符（拉丁字母、数字、混合串等）。
  other,
}

/// 分词后单元，语义对齐Python版 `Token`。
final class RubyToken {
  const RubyToken({
    required this.text,
    required this.charType,
    required this.start,
    required this.end,
    this.groupId,
  });

  final String text;
  final CharType charType;
  final int start;
  final int end;
  final int? groupId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is RubyToken &&
            text == other.text &&
            charType == other.charType &&
            start == other.start &&
            end == other.end &&
            groupId == other.groupId);
  }

  @override
  int get hashCode => Object.hash(text, charType, start, end, groupId);
}

/// 函数规则签名。
typedef RuleHandler =
    String Function(
      String anchor,
      List<RubyToken> tokens,
      int currentTokenIndex,
    );

/// 匹配规则抽象定义。
sealed class MatchRule {
  const MatchRule({required this.cost});

  final int cost;
}

/// 简单替换规则。
final class SubstitutionRule extends MatchRule {
  const SubstitutionRule({
    required super.cost,
    required this.from,
    required this.to,
  });

  final String from;
  final String to;
}

/// 函数规则。
final class FunctionRule extends MatchRule {
  const FunctionRule({required super.cost, required this.handler});

  final RuleHandler handler;
}

/// 注音结果区间。
final class RubySpan {
  const RubySpan({required this.start, required this.end, required this.ruby});

  final int start;
  final int end;
  final String ruby;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is RubySpan &&
            start == other.start &&
            end == other.end &&
            ruby == other.ruby);
  }

  @override
  int get hashCode => Object.hash(start, end, ruby);
}
