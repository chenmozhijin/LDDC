import 'package:flutter/material.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

void main() {
  runApp(const DesktopLyricsConsumerApp());
}

class DesktopLyricsConsumerApp extends StatelessWidget {
  const DesktopLyricsConsumerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final DesktopLyricsProjectionRuntime runtime =
        DesktopLyricsProjectionRuntime()
          ..bindScene(
            DesktopLyricsSceneDocument(
              mode: DesktopLyricsSceneMode.staticText,
              selectedLangs: const <String>['orig'],
              langOrder: const <String>['orig'],
              durationMs: null,
              staticDisplayLines: const <String>[
                'LDDC desktop lyrics package',
                'Independent host rendering',
              ],
            ),
          )
          ..updateFloatingStyle(
            DesktopLyricsProjectionStyle(
              enabledLangs: <String>['orig'],
              showFurigana: true,
            ),
          );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: DesktopFloatingLyricsRenderView(
            title: 'Desktop lyrics consumer',
            renderPlan: runtime.buildFloatingRenderPlan(),
            fontSize: 30,
          ),
        ),
      ),
    );
  }
}
