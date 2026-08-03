enum IntegrationReportStatus {
  passed,
  failed,
  skipped,
  blocked,
  infrastructureFailed,
}

enum IntegrationCoverageStatus { executed, skipped, blocked, liveSmoke }

extension IntegrationReportStatusJson on IntegrationReportStatus {
  String get wireName {
    return switch (this) {
      IntegrationReportStatus.passed => 'passed',
      IntegrationReportStatus.failed => 'failed',
      IntegrationReportStatus.skipped => 'skipped',
      IntegrationReportStatus.blocked => 'blocked',
      IntegrationReportStatus.infrastructureFailed => 'infrastructureFailed',
    };
  }

  bool get isSuccess => this == IntegrationReportStatus.passed;
}

extension IntegrationCoverageStatusJson on IntegrationCoverageStatus {
  String get wireName {
    return switch (this) {
      IntegrationCoverageStatus.executed => 'executed',
      IntegrationCoverageStatus.skipped => 'skipped',
      IntegrationCoverageStatus.blocked => 'blocked',
      IntegrationCoverageStatus.liveSmoke => 'liveSmoke',
    };
  }
}

IntegrationReportStatus resolveIntegrationReportStatus({
  required bool hasSteps,
  required bool hasFailedStep,
  required Map<String, Object?> extra,
}) {
  if (hasFailedStep) {
    return IntegrationReportStatus.failed;
  }
  if (extra['blocked'] == true) {
    return IntegrationReportStatus.blocked;
  }
  if (extra['skipped'] == true) {
    return IntegrationReportStatus.skipped;
  }
  if (extra['bootstrapFailed'] == true ||
      extra['setupFailed'] == true ||
      extra['infrastructureFailed'] == true ||
      extra['failed'] == true) {
    return IntegrationReportStatus.infrastructureFailed;
  }
  if (hasSteps) {
    return IntegrationReportStatus.passed;
  }

  // 空步骤既没有执行覆盖，也不能算通过；这里显式归为基础设施失败，
  // 避免测试入口提前返回或初始化失败时生成“success=true”的假绿报告。
  return IntegrationReportStatus.infrastructureFailed;
}

IntegrationCoverageStatus resolveIntegrationCoverageStatus({
  required IntegrationReportStatus status,
  required Map<String, Object?> extra,
}) {
  if (extra['coverageStatus'] is String) {
    return switch (extra['coverageStatus']) {
      'liveSmoke' => IntegrationCoverageStatus.liveSmoke,
      'blocked' => IntegrationCoverageStatus.blocked,
      'skipped' => IntegrationCoverageStatus.skipped,
      _ => IntegrationCoverageStatus.executed,
    };
  }
  return switch (status) {
    IntegrationReportStatus.skipped => IntegrationCoverageStatus.skipped,
    IntegrationReportStatus.blocked => IntegrationCoverageStatus.blocked,
    _ => IntegrationCoverageStatus.executed,
  };
}
