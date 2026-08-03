import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/i18n/i18n.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations_en.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations_zh.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  test('应用语言只为显式选择返回 locale', () {
    expect(AppLanguage.auto.explicitLocale, isNull);
    expect(
      AppLanguage.zhHans.explicitLocale,
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    );
    expect(
      AppLanguage.zhHant.explicitLocale,
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    expect(AppLanguage.en.explicitLocale, const Locale('en'));
    expect(AppLanguage.ru.explicitLocale, const Locale('ru'));
    expect(AppLanguage.ja.explicitLocale, const Locale('ja'));
    expect(AppLanguage.ko.explicitLocale, const Locale('ko'));
  });

  test('六种用户语言均由生成的本地化 delegate 提供', () {
    expect(
      AppLocalizations.supportedLocales,
      containsAll(<Locale>[
        const Locale('en'),
        const Locale('ru'),
        const Locale('ja'),
        const Locale('ko'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ]),
    );
  });

  test('系统自动语言会保留六种受支持语言并正确区分中文脚本', () {
    expect(resolveSupportedAppLocale(const Locale('ru')), const Locale('ru'));
    expect(resolveSupportedAppLocale(const Locale('ja')), const Locale('ja'));
    expect(resolveSupportedAppLocale(const Locale('ko')), const Locale('ko'));
    expect(
      resolveSupportedAppLocale(const Locale('zh', 'TW')),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    expect(
      resolveSupportedAppLocale(const Locale('zh', 'CN')),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    );
    expect(resolveSupportedAppLocale(const Locale('fr')), const Locale('en'));
  });

  test('繁体中文使用独立词形而不是简体回退', () {
    final AppLocalizations zhHant = AppLocalizationsZhHant();

    expect(zhHant.commonError, '錯誤');
    expect(zhHant.searchLyrics, '歌詞');
    expect(zhHant.navSettings, '設定');
    expect(zhHant.settingsSectionSave, '儲存');
  });

  test('歌词格式名称由本地化层统一提供', () {
    final AppLocalizations zh = AppLocalizationsZh();
    final AppLocalizations en = AppLocalizationsEn();

    expect(zh.lyricsFormatLabel(LyricsFormat.verbatimLrc), 'LRC（逐字）');
    expect(en.lyricsFormatLabel(LyricsFormat.verbatimLrc), 'Word-timed LRC');
    expect(zh.lyricsFormatLabel(LyricsFormat.ass), 'ASS');
    expect(en.lyricsFormatLabel(LyricsFormat.srt), 'SRT');
  });

  test('歌词来源与时间轴类型由本地化层统一提供', () {
    final AppLocalizations zh = AppLocalizationsZh();
    final AppLocalizations en = AppLocalizationsEn();

    expect(zh.sourceLabel(Source.qm), 'QQ音乐');
    expect(en.sourceLabel(Source.qm), 'QQ Music');
    expect(zh.lyricsTypeLabel(LyricsType.verbatim), '逐字');
    expect(en.lyricsTypeLabel(LyricsType.verbatim), 'Word-timed');
    expect(zh.lyricsTypeLabel(LyricsType.plainText), '纯文本');
    expect(en.lyricsTypeLabel(LyricsType.plainText), 'Plain text');
  });

  test('搜索类型名称由本地化层统一提供', () {
    final AppLocalizations zh = AppLocalizationsZh();
    final AppLocalizations en = AppLocalizationsEn();

    expect(zh.searchTypeLabel(SearchType.song), '单曲');
    expect(en.searchTypeLabel(SearchType.song), 'Song');
    expect(zh.searchTypeLabel(SearchType.songlist), '歌单');
    expect(en.searchTypeLabel(SearchType.songlist), 'Playlist');
    expect(zh.searchTypeLabel(SearchType.songId), '歌曲id');
    expect(en.searchTypeLabel(SearchType.songId), 'Song ID');
  });

  testWidgets('本地化 delegate 可加载中文常用文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox(),
      ),
    );

    final BuildContext context = tester.element(find.byType(SizedBox));
    final AppLocalizations l10n = AppLocalizations.of(context);

    expect(l10n.actionCancel, '取消');
    expect(l10n.localMatchIteratingFiles, '遍历文件...');
  });

  testWidgets('六种用户语言都能启动并加载关键页面文案', (WidgetTester tester) async {
    const List<Locale> locales = <Locale>[
      Locale('en'),
      Locale('ru'),
      Locale('ja'),
      Locale('ko'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    ];

    for (final Locale locale in locales) {
      late AppLocalizations loaded;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) {
              loaded = AppLocalizations.of(context);
              return Text(
                '${loaded.navSearch}|${loaded.navSettings}|${loaded.actionCancel}',
                key: const ValueKey<String>('localized_smoke_text'),
              );
            },
          ),
        ),
      );
      await tester.pump();

      final BuildContext context = tester.element(
        find.byKey(const ValueKey<String>('localized_smoke_text')),
      );
      final Locale resolved = Localizations.localeOf(context);
      expect(resolved.languageCode, locale.languageCode);
      if (locale.languageCode == 'zh') {
        expect(resolved.scriptCode, locale.scriptCode);
      }
      expect(loaded.navSearch.trim(), isNotEmpty);
      expect(loaded.navSettings.trim(), isNotEmpty);
      expect(loaded.actionCancel.trim(), isNotEmpty);
    }
  });
}
