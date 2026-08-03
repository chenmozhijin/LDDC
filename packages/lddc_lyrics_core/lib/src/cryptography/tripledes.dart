import 'dart:typed_data';

/// 三重 DES 的工作模式。
enum TripleDesMode { encrypt, decrypt }

/// 已完成校验和轮密钥展开的 QM 歌词协议 3DES 调度表。
///
/// 构造函数保持私有，调用方只能通过 [tripledesKeySetup] 获得合法实例。这样每个
/// 8 字节歌词块执行时无需再次遍历三阶段、十六轮和六字节子密钥检查结构。
final class TripleDesSchedule {
  TripleDesSchedule._(this._stages);

  final List<List<List<int>>> _stages;
}

// 重要维护说明：
// 这里不是标准 3DES 的通用实现，而是针对 QM 歌词协议的兼容实现。
// QM旧歌词解密链路依赖经过调整的 key schedule、
// 分组顺序和中间轮次结果，直接替换成 `pointycastle` 或其他标准 DESede/3DES
// 实现会导致历史 QRC/KRC 解密向量不一致。
//
//  说明与测试边界：
// - 修改任何 S-box、置换表、轮次顺序前，必须先运行 Python 基线向量测试。
// - 标准密码库只能作为对照工具，不能替代这里的运行时代码。
// - 本文件只服务歌词兼容协议，不应被复用为通用加密工具。

const List<List<int>> _sbox = <List<int>>[
  <int>[
    14,
    4,
    13,
    1,
    2,
    15,
    11,
    8,
    3,
    10,
    6,
    12,
    5,
    9,
    0,
    7,
    0,
    15,
    7,
    4,
    14,
    2,
    13,
    1,
    10,
    6,
    12,
    11,
    9,
    5,
    3,
    8,
    4,
    1,
    14,
    8,
    13,
    6,
    2,
    11,
    15,
    12,
    9,
    7,
    3,
    10,
    5,
    0,
    15,
    12,
    8,
    2,
    4,
    9,
    1,
    7,
    5,
    11,
    3,
    14,
    10,
    0,
    6,
    13,
  ],
  <int>[
    15,
    1,
    8,
    14,
    6,
    11,
    3,
    4,
    9,
    7,
    2,
    13,
    12,
    0,
    5,
    10,
    3,
    13,
    4,
    7,
    15,
    2,
    8,
    15,
    12,
    0,
    1,
    10,
    6,
    9,
    11,
    5,
    0,
    14,
    7,
    11,
    10,
    4,
    13,
    1,
    5,
    8,
    12,
    6,
    9,
    3,
    2,
    15,
    13,
    8,
    10,
    1,
    3,
    15,
    4,
    2,
    11,
    6,
    7,
    12,
    0,
    5,
    14,
    9,
  ],
  <int>[
    10,
    0,
    9,
    14,
    6,
    3,
    15,
    5,
    1,
    13,
    12,
    7,
    11,
    4,
    2,
    8,
    13,
    7,
    0,
    9,
    3,
    4,
    6,
    10,
    2,
    8,
    5,
    14,
    12,
    11,
    15,
    1,
    13,
    6,
    4,
    9,
    8,
    15,
    3,
    0,
    11,
    1,
    2,
    12,
    5,
    10,
    14,
    7,
    1,
    10,
    13,
    0,
    6,
    9,
    8,
    7,
    4,
    15,
    14,
    3,
    11,
    5,
    2,
    12,
  ],
  <int>[
    7,
    13,
    14,
    3,
    0,
    6,
    9,
    10,
    1,
    2,
    8,
    5,
    11,
    12,
    4,
    15,
    13,
    8,
    11,
    5,
    6,
    15,
    0,
    3,
    4,
    7,
    2,
    12,
    1,
    10,
    14,
    9,
    10,
    6,
    9,
    0,
    12,
    11,
    7,
    13,
    15,
    1,
    3,
    14,
    5,
    2,
    8,
    4,
    3,
    15,
    0,
    6,
    10,
    10,
    13,
    8,
    9,
    4,
    5,
    11,
    12,
    7,
    2,
    14,
  ],
  <int>[
    2,
    12,
    4,
    1,
    7,
    10,
    11,
    6,
    8,
    5,
    3,
    15,
    13,
    0,
    14,
    9,
    14,
    11,
    2,
    12,
    4,
    7,
    13,
    1,
    5,
    0,
    15,
    10,
    3,
    9,
    8,
    6,
    4,
    2,
    1,
    11,
    10,
    13,
    7,
    8,
    15,
    9,
    12,
    5,
    6,
    3,
    0,
    14,
    11,
    8,
    12,
    7,
    1,
    14,
    2,
    13,
    6,
    15,
    0,
    9,
    10,
    4,
    5,
    3,
  ],
  <int>[
    12,
    1,
    10,
    15,
    9,
    2,
    6,
    8,
    0,
    13,
    3,
    4,
    14,
    7,
    5,
    11,
    10,
    15,
    4,
    2,
    7,
    12,
    9,
    5,
    6,
    1,
    13,
    14,
    0,
    11,
    3,
    8,
    9,
    14,
    15,
    5,
    2,
    8,
    12,
    3,
    7,
    0,
    4,
    10,
    1,
    13,
    11,
    6,
    4,
    3,
    2,
    12,
    9,
    5,
    15,
    10,
    11,
    14,
    1,
    7,
    6,
    0,
    8,
    13,
  ],
  <int>[
    4,
    11,
    2,
    14,
    15,
    0,
    8,
    13,
    3,
    12,
    9,
    7,
    5,
    10,
    6,
    1,
    13,
    0,
    11,
    7,
    4,
    9,
    1,
    10,
    14,
    3,
    5,
    12,
    2,
    15,
    8,
    6,
    1,
    4,
    11,
    13,
    12,
    3,
    7,
    14,
    10,
    15,
    6,
    8,
    0,
    5,
    9,
    2,
    6,
    11,
    13,
    8,
    1,
    4,
    10,
    7,
    9,
    5,
    0,
    15,
    14,
    2,
    3,
    12,
  ],
  <int>[
    13,
    2,
    8,
    4,
    6,
    15,
    11,
    1,
    10,
    9,
    3,
    14,
    5,
    0,
    12,
    7,
    1,
    15,
    13,
    8,
    10,
    3,
    7,
    4,
    12,
    5,
    6,
    11,
    0,
    14,
    9,
    2,
    7,
    11,
    4,
    1,
    9,
    12,
    14,
    2,
    0,
    6,
    10,
    13,
    15,
    3,
    5,
    8,
    2,
    1,
    14,
    7,
    4,
    10,
    8,
    13,
    15,
    12,
    9,
    0,
    3,
    5,
    6,
    11,
  ],
];

const List<int> _keyRoundShift = <int>[
  1,
  1,
  2,
  2,
  2,
  2,
  2,
  2,
  1,
  2,
  2,
  2,
  2,
  2,
  2,
  1,
];
const List<int> _keyPermC = <int>[
  56,
  48,
  40,
  32,
  24,
  16,
  8,
  0,
  57,
  49,
  41,
  33,
  25,
  17,
  9,
  1,
  58,
  50,
  42,
  34,
  26,
  18,
  10,
  2,
  59,
  51,
  43,
  35,
];
const List<int> _keyPermD = <int>[
  62,
  54,
  46,
  38,
  30,
  22,
  14,
  6,
  61,
  53,
  45,
  37,
  29,
  21,
  13,
  5,
  60,
  52,
  44,
  36,
  28,
  20,
  12,
  4,
  27,
  19,
  11,
  3,
];
const List<int> _keyCompression = <int>[
  13,
  16,
  10,
  23,
  0,
  4,
  2,
  27,
  14,
  5,
  20,
  9,
  22,
  18,
  11,
  3,
  25,
  7,
  15,
  6,
  26,
  19,
  12,
  1,
  40,
  51,
  30,
  36,
  46,
  54,
  29,
  39,
  50,
  44,
  32,
  47,
  43,
  48,
  38,
  55,
  33,
  52,
  45,
  41,
  49,
  35,
  28,
  31,
];

/// 迁移自Python版 `tripledes.py::tripledes_key_setup`。
TripleDesSchedule tripledesKeySetup({
  required Uint8List key,
  required TripleDesMode mode,
}) {
  if (key.length != 24) {
    throw ArgumentError.value(key.length, 'key.length', '3DES key 必须正好 24 字节');
  }
  if (mode == TripleDesMode.encrypt) {
    return TripleDesSchedule._(<List<List<int>>>[
      _keySchedule(Uint8List.sublistView(key, 0, 8), TripleDesMode.encrypt),
      _keySchedule(Uint8List.sublistView(key, 8, 16), TripleDesMode.decrypt),
      _keySchedule(Uint8List.sublistView(key, 16, 24), TripleDesMode.encrypt),
    ]);
  }
  return TripleDesSchedule._(<List<List<int>>>[
    _keySchedule(Uint8List.sublistView(key, 16, 24), TripleDesMode.decrypt),
    _keySchedule(Uint8List.sublistView(key, 8, 16), TripleDesMode.encrypt),
    _keySchedule(Uint8List.sublistView(key, 0, 8), TripleDesMode.decrypt),
  ]);
}

/// 迁移自Python版 `tripledes.py::tripledes_crypt`。
Uint8List tripledesCrypt({
  required Uint8List data,
  required TripleDesSchedule schedule,
}) {
  _validateTripledesBlock(data);
  Uint8List current = Uint8List.fromList(data);
  for (final List<List<int>> stage in schedule._stages) {
    current = _crypt(current, stage);
  }
  return current;
}

void _validateTripledesBlock(Uint8List data) {
  if (data.length != 8) {
    throw ArgumentError.value(
      data.length,
      'data.length',
      '3DES data block 必须正好 8 字节',
    );
  }
}

int _bitnum(Uint8List a, int b, int c) {
  return ((a[(b ~/ 32) * 4 + 3 - ((b % 32) ~/ 8)] >> (7 - (b % 8))) & 1) << c;
}

int _bitnumIntr(int a, int b, int c) => ((a >> (31 - b)) & 1) << c;

int _bitnumIntl(int a, int b, int c) => ((a << b) & 0x80000000) >> c;

int _sboxBit(int a) => (a & 32) | ((a & 31) >> 1) | ((a & 1) << 4);

(int, int) _initialPermutation(Uint8List inputData) {
  return (
    _bitnum(inputData, 57, 31) |
        _bitnum(inputData, 49, 30) |
        _bitnum(inputData, 41, 29) |
        _bitnum(inputData, 33, 28) |
        _bitnum(inputData, 25, 27) |
        _bitnum(inputData, 17, 26) |
        _bitnum(inputData, 9, 25) |
        _bitnum(inputData, 1, 24) |
        _bitnum(inputData, 59, 23) |
        _bitnum(inputData, 51, 22) |
        _bitnum(inputData, 43, 21) |
        _bitnum(inputData, 35, 20) |
        _bitnum(inputData, 27, 19) |
        _bitnum(inputData, 19, 18) |
        _bitnum(inputData, 11, 17) |
        _bitnum(inputData, 3, 16) |
        _bitnum(inputData, 61, 15) |
        _bitnum(inputData, 53, 14) |
        _bitnum(inputData, 45, 13) |
        _bitnum(inputData, 37, 12) |
        _bitnum(inputData, 29, 11) |
        _bitnum(inputData, 21, 10) |
        _bitnum(inputData, 13, 9) |
        _bitnum(inputData, 5, 8) |
        _bitnum(inputData, 63, 7) |
        _bitnum(inputData, 55, 6) |
        _bitnum(inputData, 47, 5) |
        _bitnum(inputData, 39, 4) |
        _bitnum(inputData, 31, 3) |
        _bitnum(inputData, 23, 2) |
        _bitnum(inputData, 15, 1) |
        _bitnum(inputData, 7, 0),
    _bitnum(inputData, 56, 31) |
        _bitnum(inputData, 48, 30) |
        _bitnum(inputData, 40, 29) |
        _bitnum(inputData, 32, 28) |
        _bitnum(inputData, 24, 27) |
        _bitnum(inputData, 16, 26) |
        _bitnum(inputData, 8, 25) |
        _bitnum(inputData, 0, 24) |
        _bitnum(inputData, 58, 23) |
        _bitnum(inputData, 50, 22) |
        _bitnum(inputData, 42, 21) |
        _bitnum(inputData, 34, 20) |
        _bitnum(inputData, 26, 19) |
        _bitnum(inputData, 18, 18) |
        _bitnum(inputData, 10, 17) |
        _bitnum(inputData, 2, 16) |
        _bitnum(inputData, 60, 15) |
        _bitnum(inputData, 52, 14) |
        _bitnum(inputData, 44, 13) |
        _bitnum(inputData, 36, 12) |
        _bitnum(inputData, 28, 11) |
        _bitnum(inputData, 20, 10) |
        _bitnum(inputData, 12, 9) |
        _bitnum(inputData, 4, 8) |
        _bitnum(inputData, 62, 7) |
        _bitnum(inputData, 54, 6) |
        _bitnum(inputData, 46, 5) |
        _bitnum(inputData, 38, 4) |
        _bitnum(inputData, 30, 3) |
        _bitnum(inputData, 22, 2) |
        _bitnum(inputData, 14, 1) |
        _bitnum(inputData, 6, 0),
  );
}

Uint8List _inversePermutation(int s0, int s1) {
  final Uint8List data = Uint8List(8);
  data[3] =
      _bitnumIntr(s1, 7, 7) |
      _bitnumIntr(s0, 7, 6) |
      _bitnumIntr(s1, 15, 5) |
      _bitnumIntr(s0, 15, 4) |
      _bitnumIntr(s1, 23, 3) |
      _bitnumIntr(s0, 23, 2) |
      _bitnumIntr(s1, 31, 1) |
      _bitnumIntr(s0, 31, 0);
  data[2] =
      _bitnumIntr(s1, 6, 7) |
      _bitnumIntr(s0, 6, 6) |
      _bitnumIntr(s1, 14, 5) |
      _bitnumIntr(s0, 14, 4) |
      _bitnumIntr(s1, 22, 3) |
      _bitnumIntr(s0, 22, 2) |
      _bitnumIntr(s1, 30, 1) |
      _bitnumIntr(s0, 30, 0);
  data[1] =
      _bitnumIntr(s1, 5, 7) |
      _bitnumIntr(s0, 5, 6) |
      _bitnumIntr(s1, 13, 5) |
      _bitnumIntr(s0, 13, 4) |
      _bitnumIntr(s1, 21, 3) |
      _bitnumIntr(s0, 21, 2) |
      _bitnumIntr(s1, 29, 1) |
      _bitnumIntr(s0, 29, 0);
  data[0] =
      _bitnumIntr(s1, 4, 7) |
      _bitnumIntr(s0, 4, 6) |
      _bitnumIntr(s1, 12, 5) |
      _bitnumIntr(s0, 12, 4) |
      _bitnumIntr(s1, 20, 3) |
      _bitnumIntr(s0, 20, 2) |
      _bitnumIntr(s1, 28, 1) |
      _bitnumIntr(s0, 28, 0);
  data[7] =
      _bitnumIntr(s1, 3, 7) |
      _bitnumIntr(s0, 3, 6) |
      _bitnumIntr(s1, 11, 5) |
      _bitnumIntr(s0, 11, 4) |
      _bitnumIntr(s1, 19, 3) |
      _bitnumIntr(s0, 19, 2) |
      _bitnumIntr(s1, 27, 1) |
      _bitnumIntr(s0, 27, 0);
  data[6] =
      _bitnumIntr(s1, 2, 7) |
      _bitnumIntr(s0, 2, 6) |
      _bitnumIntr(s1, 10, 5) |
      _bitnumIntr(s0, 10, 4) |
      _bitnumIntr(s1, 18, 3) |
      _bitnumIntr(s0, 18, 2) |
      _bitnumIntr(s1, 26, 1) |
      _bitnumIntr(s0, 26, 0);
  data[5] =
      _bitnumIntr(s1, 1, 7) |
      _bitnumIntr(s0, 1, 6) |
      _bitnumIntr(s1, 9, 5) |
      _bitnumIntr(s0, 9, 4) |
      _bitnumIntr(s1, 17, 3) |
      _bitnumIntr(s0, 17, 2) |
      _bitnumIntr(s1, 25, 1) |
      _bitnumIntr(s0, 25, 0);
  data[4] =
      _bitnumIntr(s1, 0, 7) |
      _bitnumIntr(s0, 0, 6) |
      _bitnumIntr(s1, 8, 5) |
      _bitnumIntr(s0, 8, 4) |
      _bitnumIntr(s1, 16, 3) |
      _bitnumIntr(s0, 16, 2) |
      _bitnumIntr(s1, 24, 1) |
      _bitnumIntr(s0, 24, 0);
  return data;
}

int _f(int state, List<int> key) {
  final int t1 =
      _bitnumIntl(state, 31, 0) |
      ((state & 0xf0000000) >> 1) |
      _bitnumIntl(state, 4, 5) |
      _bitnumIntl(state, 3, 6) |
      ((state & 0x0f000000) >> 3) |
      _bitnumIntl(state, 8, 11) |
      _bitnumIntl(state, 7, 12) |
      ((state & 0x00f00000) >> 5) |
      _bitnumIntl(state, 12, 17) |
      _bitnumIntl(state, 11, 18) |
      ((state & 0x000f0000) >> 7) |
      _bitnumIntl(state, 16, 23);

  final int t2 =
      _bitnumIntl(state, 15, 0) |
      ((state & 0x0000f000) << 15) |
      _bitnumIntl(state, 20, 5) |
      _bitnumIntl(state, 19, 6) |
      ((state & 0x00000f00) << 13) |
      _bitnumIntl(state, 24, 11) |
      _bitnumIntl(state, 23, 12) |
      ((state & 0x000000f0) << 11) |
      _bitnumIntl(state, 28, 17) |
      _bitnumIntl(state, 27, 18) |
      ((state & 0x0000000f) << 9) |
      _bitnumIntl(state, 0, 23);

  final List<int> lrgState = <int>[
    (t1 >> 24) & 0xff,
    (t1 >> 16) & 0xff,
    (t1 >> 8) & 0xff,
    (t2 >> 24) & 0xff,
    (t2 >> 16) & 0xff,
    (t2 >> 8) & 0xff,
  ];
  for (int i = 0; i < 6; i++) {
    lrgState[i] = lrgState[i] ^ key[i];
  }

  state =
      (_sbox[0][_sboxBit(lrgState[0] >> 2)] << 28) |
      (_sbox[1][_sboxBit(((lrgState[0] & 0x03) << 4) | (lrgState[1] >> 4))] <<
          24) |
      (_sbox[2][_sboxBit(((lrgState[1] & 0x0f) << 2) | (lrgState[2] >> 6))] <<
          20) |
      (_sbox[3][_sboxBit(lrgState[2] & 0x3f)] << 16) |
      (_sbox[4][_sboxBit(lrgState[3] >> 2)] << 12) |
      (_sbox[5][_sboxBit(((lrgState[3] & 0x03) << 4) | (lrgState[4] >> 4))] <<
          8) |
      (_sbox[6][_sboxBit(((lrgState[4] & 0x0f) << 2) | (lrgState[5] >> 6))] <<
          4) |
      _sbox[7][_sboxBit(lrgState[5] & 0x3f)];

  return (_bitnumIntl(state, 15, 0) |
          _bitnumIntl(state, 6, 1) |
          _bitnumIntl(state, 19, 2) |
          _bitnumIntl(state, 20, 3) |
          _bitnumIntl(state, 28, 4) |
          _bitnumIntl(state, 11, 5) |
          _bitnumIntl(state, 27, 6) |
          _bitnumIntl(state, 16, 7) |
          _bitnumIntl(state, 0, 8) |
          _bitnumIntl(state, 14, 9) |
          _bitnumIntl(state, 22, 10) |
          _bitnumIntl(state, 25, 11) |
          _bitnumIntl(state, 4, 12) |
          _bitnumIntl(state, 17, 13) |
          _bitnumIntl(state, 30, 14) |
          _bitnumIntl(state, 9, 15) |
          _bitnumIntl(state, 1, 16) |
          _bitnumIntl(state, 7, 17) |
          _bitnumIntl(state, 23, 18) |
          _bitnumIntl(state, 13, 19) |
          _bitnumIntl(state, 31, 20) |
          _bitnumIntl(state, 26, 21) |
          _bitnumIntl(state, 2, 22) |
          _bitnumIntl(state, 8, 23) |
          _bitnumIntl(state, 18, 24) |
          _bitnumIntl(state, 12, 25) |
          _bitnumIntl(state, 29, 26) |
          _bitnumIntl(state, 5, 27) |
          _bitnumIntl(state, 21, 28) |
          _bitnumIntl(state, 10, 29) |
          _bitnumIntl(state, 3, 30) |
          _bitnumIntl(state, 24, 31)) &
      0xffffffff;
}

Uint8List _crypt(Uint8List inputData, List<List<int>> key) {
  final (int initialS0, int initialS1) = _initialPermutation(inputData);
  int s0 = initialS0;
  int s1 = initialS1;
  for (int idx = 0; idx < 15; idx++) {
    final int previousS1 = s1;
    s1 = (_f(s1, key[idx]) ^ s0) & 0xffffffff;
    s0 = previousS1;
  }
  s0 = (_f(s1, key[15]) ^ s0) & 0xffffffff;
  return _inversePermutation(s0, s1);
}

List<List<int>> _keySchedule(Uint8List key, TripleDesMode mode) {
  final List<List<int>> schedule = List<List<int>>.generate(
    16,
    (_) => List<int>.filled(6, 0),
  );

  int c = 0;
  int d = 0;
  for (int i = 0; i < 28; i++) {
    c += _bitnum(key, _keyPermC[i], 31 - i);
    d += _bitnum(key, _keyPermD[i], 31 - i);
  }

  for (int i = 0; i < 16; i++) {
    final int shift = _keyRoundShift[i];
    c = ((c << shift) | (c >> (28 - shift))) & 0xfffffff0;
    d = ((d << shift) | (d >> (28 - shift))) & 0xfffffff0;
    final int togen = mode == TripleDesMode.decrypt ? (15 - i) : i;

    for (int j = 0; j < 6; j++) {
      schedule[togen][j] = 0;
    }
    for (int j = 0; j < 24; j++) {
      schedule[togen][j ~/ 8] |= _bitnumIntr(
        c,
        _keyCompression[j],
        7 - (j % 8),
      );
    }
    for (int j = 24; j < 48; j++) {
      schedule[togen][j ~/ 8] |= _bitnumIntr(
        d,
        _keyCompression[j] - 27,
        7 - (j % 8),
      );
    }
  }
  return schedule;
}
