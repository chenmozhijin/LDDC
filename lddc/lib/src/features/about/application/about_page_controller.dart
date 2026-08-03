import 'dart:ui';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/about/about_ports.dart';
import '../../../core/app_metadata.dart';
import '../../../core/config/config.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/i18n/l10n/app_localizations.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'about_page_dependencies.dart';
import 'about_page_models.dart';

part 'about_page_controller.g.dart';

const String _kAboutRepositoryUrl = 'https://github.com/chenmozhijin/LDDC';
const String _kAboutIssueTrackerUrl =
    'https://github.com/chenmozhijin/LDDC/issues';
const String _kAboutLicenseUrl =
    'https://github.com/chenmozhijin/LDDC/blob/master/LICENSE';
const String _kAboutChangelogUrl =
    'https://github.com/chenmozhijin/LDDC/releases';
const String _kAboutAuthorName = '沉默の金';
const String _kAboutLicenseName = 'GPL-3.0-only';
const String _kAboutIconAsset = 'assets/tray_icon.png';

// 关于页依赖可由页面级 ProviderScope 覆写，因此控制器必须显式声明传递依赖，
// 让 Riverpod 3.4 将控制器实例绑定到正确的子作用域并安全释放。
@Riverpod(keepAlive: true, dependencies: [aboutPageDependencies])
class AboutPageController extends _$AboutPageController {
  @override
  Future<PageViewState<AboutPagePayload>> build() async {
    ref.watch(aboutPageDependenciesProvider);
    return _buildState();
  }

  Future<void> reload() async {
    state = const AsyncValue<PageViewState<AboutPagePayload>>.loading();
    try {
      final PageViewState<AboutPagePayload> next = await _buildState();
      state = AsyncValue<PageViewState<AboutPagePayload>>.data(next);
    } catch (error, stackTrace) {
      state = AsyncValue<PageViewState<AboutPagePayload>>.error(
        error,
        stackTrace,
      );
    }
  }

  Future<AboutActionResult> openRepository() {
    return _openExternalLink(
      actionType: AboutActionType.repository,
      uri: Uri.parse(_kAboutRepositoryUrl),
    );
  }

  Future<AboutActionResult> openIssueTracker() {
    return _openProjectLink(
      kind: AboutActionLinkKind.issues,
      actionType: AboutActionType.issueTracker,
    );
  }

  Future<AboutActionResult> openLicense() {
    return _openProjectLink(
      kind: AboutActionLinkKind.license,
      actionType: AboutActionType.license,
    );
  }

  Future<AboutActionResult> openChangelog() {
    return _openProjectLink(
      kind: AboutActionLinkKind.changelog,
      actionType: AboutActionType.changelog,
    );
  }

  Future<AboutActionResult> checkForUpdates() {
    final Uri releaseUri = Uri.parse(_kAboutChangelogUrl);
    return _runTrackedAction(
      actionType: AboutActionType.checkForUpdates,
      uri: releaseUri,
      operation: () async {
        final AppUpdatePort updatePort = ref
            .read(aboutPageDependenciesProvider)
            .updatePort;
        final AppUpdateCheckResult result = await updatePort.checkForUpdates(
          releaseUri: releaseUri,
        );
        if (!result.isSupported) {
          return AboutActionResult.unsupported(
            actionType: AboutActionType.checkForUpdates,
          );
        }
        if (result.status == AppUpdateStatus.upToDate) {
          return AboutActionResult.upToDate(
            actionType: AboutActionType.checkForUpdates,
            latestVersion: result.latestVersion,
          );
        }
        if (result.status == AppUpdateStatus.updateAvailable &&
            result.releaseUri != null &&
            result.latestVersion != null) {
          return AboutActionResult.updateAvailable(
            actionType: AboutActionType.checkForUpdates,
            uri: result.releaseUri!,
            latestVersion: result.latestVersion!,
          );
        }
        return AboutActionResult.failed(
          actionType: AboutActionType.checkForUpdates,
          error: result.error ?? StateError('check-update-failed'),
          uri: releaseUri,
        );
      },
    );
  }

  AboutPagePayload? get _currentPayload {
    final PageViewState<AboutPagePayload>? current = state.asData?.value;
    if (current == null) {
      return null;
    }
    return switch (current.view) {
      AsyncSuccess<AboutPagePayload>(:final data) => data,
      AsyncPartial<AboutPagePayload>(:final data) => data,
      _ => null,
    };
  }

  Future<AboutActionResult> _openProjectLink({
    required AboutActionLinkKind kind,
    required AboutActionType actionType,
  }) async {
    final AboutPagePayload? payload = _currentPayload;
    if (payload == null) {
      return AboutActionResult.failed(
        actionType: actionType,
        error: StateError('about-page-not-ready'),
      );
    }
    final AboutActionLink? link = payload.findProjectLink(kind);
    if (link == null) {
      return AboutActionResult.failed(
        actionType: actionType,
        error: StateError('about-link-missing-${kind.name}'),
      );
    }
    return _openExternalLink(actionType: actionType, uri: link.uri);
  }

  Future<AboutActionResult> _openExternalLink({
    required AboutActionType actionType,
    required Uri uri,
  }) {
    return _runTrackedAction(
      actionType: actionType,
      uri: uri,
      operation: () async {
        final AppLinkOpener opener = ref
            .read(aboutPageDependenciesProvider)
            .linkOpener;
        if (!opener.isSupported) {
          return AboutActionResult.unsupported(actionType: actionType);
        }
        await opener.openExternalUri(uri);
        return AboutActionResult.opened(actionType: actionType, uri: uri);
      },
    );
  }

  Future<AboutActionResult> _runTrackedAction({
    required AboutActionType actionType,
    required Uri uri,
    required Future<AboutActionResult> Function() operation,
  }) async {
    if (!_beginAction(actionType)) {
      return AboutActionResult.failed(
        actionType: actionType,
        error: StateError(
          _currentPayload == null
              ? 'about-page-not-ready'
              : 'about-action-busy',
        ),
        uri: uri,
      );
    }
    try {
      return await operation();
    } catch (error) {
      return AboutActionResult.failed(
        actionType: actionType,
        error: error,
        uri: uri,
      );
    } finally {
      _finishAction(actionType);
    }
  }

  bool _beginAction(AboutActionType actionType) {
    final PageViewState<AboutPagePayload>? current = state.asData?.value;
    final AboutPagePayload? payload = _payloadOf(current?.view);
    if (current == null || payload == null || payload.isBusy) {
      return false;
    }
    state = AsyncValue<PageViewState<AboutPagePayload>>.data(
      current.copyWith(
        view: _replacePayload(
          current.view,
          payload.copyWith(activeAction: actionType),
        ),
        action: current.action.copyWith(phase: PageActionPhase.running),
        lastUpdatedAt: DateTime.now(),
      ),
    );
    return true;
  }

  void _finishAction(AboutActionType actionType) {
    final PageViewState<AboutPagePayload>? current = state.asData?.value;
    final AboutPagePayload? payload = _payloadOf(current?.view);
    if (current == null || payload?.activeAction != actionType) {
      return;
    }
    state = AsyncValue<PageViewState<AboutPagePayload>>.data(
      current.copyWith(
        view: _replacePayload(
          current.view,
          payload!.copyWith(clearActiveAction: true),
        ),
        action: current.action.copyWith(
          phase: PageActionPhase.idle,
          clearMessage: true,
        ),
        lastUpdatedAt: DateTime.now(),
      ),
    );
  }

  AboutPagePayload? _payloadOf(AsyncViewState<AboutPagePayload>? view) {
    return switch (view) {
      AsyncSuccess<AboutPagePayload>(:final data) => data,
      AsyncPartial<AboutPagePayload>(:final data) => data,
      _ => null,
    };
  }

  AsyncViewState<AboutPagePayload> _replacePayload(
    AsyncViewState<AboutPagePayload> view,
    AboutPagePayload payload,
  ) {
    return switch (view) {
      AsyncSuccess<AboutPagePayload>() => AsyncSuccess<AboutPagePayload>(
        data: payload,
      ),
      AsyncPartial<AboutPagePayload>(:final message, :final warningMessage) =>
        AsyncPartial<AboutPagePayload>(
          data: payload,
          message: message,
          warningMessage: warningMessage,
        ),
      _ => view,
    };
  }

  Future<PageViewState<AboutPagePayload>> _buildState() async {
    final AboutPageDependencies dependencies = ref.read(
      aboutPageDependenciesProvider,
    );
    final ConfigRepository repository = dependencies.configRepository;
    final AppConfig config = await repository.load();
    final AppLocalizations l10n = lookupAppLocalizations(
      _resolveLocale(config.app.language),
    );
    final int year = DateTime.now().year;
    final String yearRange = year <= 2024 ? '2024' : '2024-$year';
    final AboutPagePayload payload = AboutPagePayload(
      appIconAsset: _kAboutIconAsset,
      appName: 'LDDC',
      headline: l10n.aboutHeroHeadline,
      description: l10n.aboutHeroDescription,
      versionLabel: kLddcVersion,
      copyrightYearRange: yearRange,
      authorName: _kAboutAuthorName,
      canCheckUpdate: dependencies.updatePort.isSupported,
      canOpenExternalLinks: dependencies.linkOpener.isSupported,
      projectLinks: <AboutActionLink>[
        AboutActionLink(
          kind: AboutActionLinkKind.issues,
          title: l10n.aboutLinkIssueTrackerTitle,
          supportingText: l10n.aboutLinkIssueTrackerDescription,
          uri: Uri.parse(_kAboutIssueTrackerUrl),
        ),
        AboutActionLink(
          kind: AboutActionLinkKind.license,
          title: l10n.aboutLinkLicenseTitle,
          supportingText:
              '${l10n.aboutLinkLicenseDescription} $_kAboutLicenseName',
          uri: Uri.parse(_kAboutLicenseUrl),
        ),
        AboutActionLink(
          kind: AboutActionLinkKind.changelog,
          title: l10n.aboutLinkChangelogTitle,
          supportingText: l10n.aboutLinkChangelogDescription,
          uri: Uri.parse(_kAboutChangelogUrl),
        ),
      ],
    );
    return PageViewState<AboutPagePayload>(
      view: AsyncSuccess<AboutPagePayload>(data: payload),
      lastUpdatedAt: DateTime.now(),
    );
  }

  Locale _resolveLocale(AppLanguage language) {
    return language.explicitLocale ??
        resolveSupportedAppLocale(PlatformDispatcher.instance.locale);
  }
}
