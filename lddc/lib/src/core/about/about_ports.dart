abstract interface class AppLinkOpener {
  bool get isSupported;

  Future<void> openExternalUri(Uri uri);
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult._({
    required this.isSupported,
    required this.status,
    this.latestVersion,
    this.releaseUri,
    this.error,
  });

  final bool isSupported;
  final AppUpdateStatus status;
  final String? latestVersion;
  final Uri? releaseUri;
  final Object? error;

  factory AppUpdateCheckResult.updateAvailable({
    required String latestVersion,
    required Uri releaseUri,
  }) {
    return AppUpdateCheckResult._(
      isSupported: true,
      status: AppUpdateStatus.updateAvailable,
      latestVersion: latestVersion,
      releaseUri: releaseUri,
    );
  }

  factory AppUpdateCheckResult.upToDate({String? latestVersion}) {
    return AppUpdateCheckResult._(
      isSupported: true,
      status: AppUpdateStatus.upToDate,
      latestVersion: latestVersion,
    );
  }

  factory AppUpdateCheckResult.unsupported() {
    return const AppUpdateCheckResult._(
      isSupported: false,
      status: AppUpdateStatus.unsupported,
    );
  }

  factory AppUpdateCheckResult.failed(Object error) {
    return AppUpdateCheckResult._(
      isSupported: true,
      status: AppUpdateStatus.failed,
      error: error,
    );
  }
}

enum AppUpdateStatus { unsupported, upToDate, updateAvailable, failed }

abstract interface class AppUpdatePort {
  bool get isSupported;

  Future<AppUpdateCheckResult> checkForUpdates({required Uri releaseUri});
}

abstract interface class CloseableAppUpdatePort implements AppUpdatePort {
  Future<void> close();
}

class UnsupportedAppUpdatePort implements AppUpdatePort {
  const UnsupportedAppUpdatePort();

  @override
  bool get isSupported => false;

  @override
  Future<AppUpdateCheckResult> checkForUpdates({
    required Uri releaseUri,
  }) async {
    return AppUpdateCheckResult.unsupported();
  }
}
