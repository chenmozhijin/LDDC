enum AboutActionLinkKind { issues, license, changelog }

enum AboutActionType {
  repository,
  issueTracker,
  license,
  changelog,
  checkForUpdates,
}

enum AboutActionResultType {
  opened,
  unsupported,
  failed,
  upToDate,
  updateAvailable,
}

class AboutActionLink {
  const AboutActionLink({
    required this.kind,
    required this.title,
    required this.supportingText,
    required this.uri,
  });

  final AboutActionLinkKind kind;
  final String title;
  final String supportingText;
  final Uri uri;
}

class AboutActionResult {
  const AboutActionResult._({
    required this.type,
    required this.actionType,
    this.uri,
    this.latestVersion,
    this.error,
  });

  final AboutActionResultType type;
  final AboutActionType actionType;
  final Uri? uri;
  final String? latestVersion;
  final Object? error;

  factory AboutActionResult.opened({
    required AboutActionType actionType,
    required Uri uri,
  }) {
    return AboutActionResult._(
      type: AboutActionResultType.opened,
      actionType: actionType,
      uri: uri,
    );
  }

  factory AboutActionResult.unsupported({required AboutActionType actionType}) {
    return AboutActionResult._(
      type: AboutActionResultType.unsupported,
      actionType: actionType,
    );
  }

  factory AboutActionResult.failed({
    required AboutActionType actionType,
    required Object error,
    Uri? uri,
  }) {
    return AboutActionResult._(
      type: AboutActionResultType.failed,
      actionType: actionType,
      uri: uri,
      error: error,
    );
  }

  factory AboutActionResult.upToDate({
    required AboutActionType actionType,
    String? latestVersion,
  }) {
    return AboutActionResult._(
      type: AboutActionResultType.upToDate,
      actionType: actionType,
      latestVersion: latestVersion,
    );
  }

  factory AboutActionResult.updateAvailable({
    required AboutActionType actionType,
    required Uri uri,
    required String latestVersion,
  }) {
    return AboutActionResult._(
      type: AboutActionResultType.updateAvailable,
      actionType: actionType,
      uri: uri,
      latestVersion: latestVersion,
    );
  }
}

/// 关于页载荷：承载品牌、核心动作与次级资源入口。
class AboutPagePayload {
  AboutPagePayload({
    required this.appIconAsset,
    required this.appName,
    required this.headline,
    required this.description,
    required this.versionLabel,
    required this.copyrightYearRange,
    required this.authorName,
    required this.canCheckUpdate,
    required this.canOpenExternalLinks,
    required List<AboutActionLink> projectLinks,
    this.activeAction,
  }) : projectLinks = List<AboutActionLink>.unmodifiable(projectLinks);

  final String appIconAsset;
  final String appName;
  final String headline;
  final String description;
  final String versionLabel;
  final String copyrightYearRange;
  final String authorName;
  final bool canCheckUpdate;
  final bool canOpenExternalLinks;
  final List<AboutActionLink> projectLinks;
  final AboutActionType? activeAction;

  bool get isBusy => activeAction != null;

  bool isRunning(AboutActionType actionType) => activeAction == actionType;

  AboutActionLink? findProjectLink(AboutActionLinkKind kind) {
    for (final AboutActionLink link in projectLinks) {
      if (link.kind == kind) {
        return link;
      }
    }
    return null;
  }

  AboutPagePayload copyWith({
    String? appIconAsset,
    String? appName,
    String? headline,
    String? description,
    String? versionLabel,
    String? copyrightYearRange,
    String? authorName,
    bool? canCheckUpdate,
    bool? canOpenExternalLinks,
    List<AboutActionLink>? projectLinks,
    AboutActionType? activeAction,
    bool clearActiveAction = false,
  }) {
    return AboutPagePayload(
      appIconAsset: appIconAsset ?? this.appIconAsset,
      appName: appName ?? this.appName,
      headline: headline ?? this.headline,
      description: description ?? this.description,
      versionLabel: versionLabel ?? this.versionLabel,
      copyrightYearRange: copyrightYearRange ?? this.copyrightYearRange,
      authorName: authorName ?? this.authorName,
      canCheckUpdate: canCheckUpdate ?? this.canCheckUpdate,
      canOpenExternalLinks: canOpenExternalLinks ?? this.canOpenExternalLinks,
      projectLinks: projectLinks ?? this.projectLinks,
      activeAction: clearActiveAction
          ? null
          : (activeAction ?? this.activeAction),
    );
  }
}
