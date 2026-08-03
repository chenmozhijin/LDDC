import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:test/test.dart';

void main() {
  group('QmParamGenerator 虚构设备协议', () {
    test('包含 IMEI 时生成确定的 did、UDID、aid 与加密参数', () {
      const int currentTimeMs = 1710000000123;
      const QmDeviceProfile profile = QmDeviceProfile(
        imei: '861234567890123',
        simSerial: '8986001234567890123',
        mcc: '460',
        mnc: '01',
      );
      final QmParamGenerator generator = QmParamGenerator(
        profile: profile,
        identity: QmDeviceIdentity(
          generation: 0,
          androidId: '0123456789abcdef',
          openUdid2: generateQmOpenUdid2(
            '0123456789abcdef',
            profile.imei,
            currentTimeMs,
          ),
          dataLocalSnapshot: generateQmDataLocalSnapshot(
            profile,
            currentTimeMs: currentTimeMs,
          ),
        ),
        teaRandomSourceFactory: () => ReplayQmParamRandomSource(
          byteValues: const <int>[215, 19, 185, 77],
        ),
      );

      expect(generator.did, 'ODYxMjM0NTY3ODkwMTIz');
      expect(generator.openUdid, '00000000110386a818f34379fa935018');
      expect(generator.openUdid2, '00000000110386a80000018e3bf34f7b');
      expect(generator.aid, '0123456789abcdef');
      expect(
        generator.mValue,
        'ArmiGPGWRNtGJUzg+7Le9r1rDpWYDCxjfFBn0efJSkpq/CEwSNELh9WP0GsXr0rpMQJ7jQD19WzaQkOYDNPHgQ==',
      );
    });

    test('缺少 IMEI 时 did 为空但其他虚构设备字段仍可生成', () {
      const int currentTimeMs = 1710001234567;
      const QmDeviceProfile profile = QmDeviceProfile(
        imei: '',
        simSerial: 'null',
        mcc: '460',
        mnc: '01',
      );
      final QmParamGenerator generator = QmParamGenerator(
        profile: profile,
        identity: QmDeviceIdentity(
          generation: 0,
          androidId: 'fedcba9876543210',
          openUdid2: generateQmOpenUdid2(
            'fedcba9876543210',
            profile.imei,
            currentTimeMs,
          ),
          dataLocalSnapshot: generateQmDataLocalSnapshot(
            profile,
            currentTimeMs: currentTimeMs,
          ),
        ),
        teaRandomSourceFactory: () => ReplayQmParamRandomSource(
          byteValues: const <int>[229, 166, 92, 1, 49, 184, 19, 93],
        ),
      );

      expect(generator.did, isEmpty);
      expect(generator.openUdid, 'ffffffffd24fcd98000000000033c587');
      expect(generator.openUdid2, 'ffffffffd24fcd980000018e2437e787');
      expect(generator.aid, 'fedcba9876543210');
      expect(
        generator.mValue,
        'oHFZpSKPTwH1t2I271hL+O6TL9ezn2lyZiWHXjSho4l6LJx00w0hJog7MjMb//Y6',
      );
    });
  });
}
