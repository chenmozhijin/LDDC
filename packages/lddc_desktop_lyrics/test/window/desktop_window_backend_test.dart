import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

void main() {
  group('桌面窗口公共契约', () {
    test('浮窗会话冻结集合并只携带播放器无关事件', () {
      final List<String> langs = <String>['orig'];
      final List<RgbColor> colors = <RgbColor>[const RgbColor(1, 2, 3)];
      final DesktopFloatingSessionSnapshot session =
          DesktopFloatingSessionSnapshot(
            enabledLangs: langs,
            playedColors: colors,
          );
      const DesktopFloatingAnchorSnapshot anchor =
          DesktopFloatingAnchorSnapshot(
            eventKind: DesktopPlaybackEventKind.trackChanged,
          );

      langs.add('ts');
      colors.add(const RgbColor(4, 5, 6));

      expect(session.enabledLangs, const <String>['orig']);
      expect(session.playedColors, const <RgbColor>[RgbColor(1, 2, 3)]);
      expect(anchor.eventKind, DesktopPlaybackEventKind.trackChanged);
      expect(() => session.enabledLangs.add('roma'), throwsUnsupportedError);
    });

    test('子 engine 的空宿主不会创建窗口或持有资源', () async {
      const DesktopNoopFloatingWindowHost floatingHost =
          DesktopNoopFloatingWindowHost();
      const DesktopNoopSelectorWindowHost selectorHost =
          DesktopNoopSelectorWindowHost();

      await floatingHost.applyFloatingSnapshot(
        instanceId: 1,
        snapshot: DesktopFloatingWindowSnapshot(
          session: const DesktopFloatingSessionSnapshot.empty(),
        ),
      );
      expect(await floatingHost.flushFloatingGeometry(instanceId: 1), isTrue);
      await floatingHost.destroyFloatingWindow(instanceId: 1);
      await selectorHost.ensureSelectorWindow(instanceId: 1);
      await selectorHost.hideSelectorWindow(instanceId: 1);
      await selectorHost.destroySelectorWindow(instanceId: 1);
    });
  });
}
