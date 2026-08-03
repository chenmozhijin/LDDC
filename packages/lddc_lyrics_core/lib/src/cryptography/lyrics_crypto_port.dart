import 'dart:typed_data';

import 'tripledes.dart';

/// 歌词加密模块统一端口。
///
/// 该端口只保留歌词解密器需要替换的 QMC1 与 QM 协议 3DES 能力。EAPI、
/// QM 参数签名和 TEA 都是无状态算法，生产代码直接调用对应模块函数，避免为测试
/// 再维护一层没有业务所有权的转发接口。
abstract interface class LyricsCryptoPort {
  Uint8List qmc1Decrypt(Uint8List data);

  TripleDesSchedule tripledesKeySetup({
    required Uint8List key,
    required TripleDesMode mode,
  });

  Uint8List tripledesCrypt({
    required Uint8List data,
    required TripleDesSchedule schedule,
  });
}
