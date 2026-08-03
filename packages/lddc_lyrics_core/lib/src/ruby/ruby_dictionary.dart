part 'ruby_dictionary_data.g.dart';

/// 词典 Trie 节点使用 Unicode 码点作为边，查找时不需要反复创建单字符字符串。
final class _TrieNode {
  final Map<int, _TrieNode> children = <int, _TrieNode>{};
  List<String>? readings;
}

final _TrieNode _jpVocabTrie = _buildVocabTrie();

_TrieNode _buildVocabTrie() {
  final _TrieNode root = _TrieNode();
  _populateRubyVocabulary(root);
  return root;
}

/// 由生成文件逐条调用，把 Python 词典直接写入 Trie。
///
/// 生成阶段不再创建一份长期驻留的 Map，因此运行时只保留实际查询需要的
/// Trie 和读音列表，避免同一批词条同时以 Map 与 Trie 两种结构常驻内存。
void _insertRubyVocabulary(_TrieNode root, String word, List<String> readings) {
  _TrieNode node = root;
  for (final int rune in word.runes) {
    node = node.children.putIfAbsent(rune, _TrieNode.new);
  }
  node.readings = readings;
}

/// 从 [characters] 的 [start] 位置开始，返回词典中最长前缀的 grapheme 数。
///
/// 分词器已经持有整行的 grapheme 列表，因此这里直接沿 Trie 前进，不构造
/// “剩余字符串”、前缀字符串或候选列表。只有完整消费一个 grapheme 后才记录
/// 命中，保证返回长度可以直接用于 RubySpan 的 grapheme 索引。
int findLongestVocabPrefixLength(List<String> characters, int start) {
  _TrieNode node = _jpVocabTrie;
  int longestLength = 0;

  for (int index = start; index < characters.length; index += 1) {
    for (final int rune in characters[index].runes) {
      final _TrieNode? next = node.children[rune];
      if (next == null) {
        return longestLength;
      }
      node = next;
    }
    if (node.readings != null) {
      longestLength = index - start + 1;
    }
  }
  return longestLength;
}

List<String>? findVocabWord(String word) {
  _TrieNode node = _jpVocabTrie;
  for (final int rune in word.runes) {
    final _TrieNode? next = node.children[rune];
    if (next == null) {
      return null;
    }
    node = next;
  }
  return node.readings;
}
