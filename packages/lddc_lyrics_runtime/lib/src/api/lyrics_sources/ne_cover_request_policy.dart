import 'ne_client_profile.dart';

/// NE图片 CDN 的统一请求策略。
///
/// Provider、Flutter 图片组件和真实请求测试必须复用这里的规则，避免 URL、
/// User-Agent 或 CDN 回退顺序分别维护后再次发生行为漂移。
abstract final class NeCoverRequestPolicy {
  static const List<String> cdnHosts = <String>[
    'p1.music.126.net',
    'p3.music.126.net',
    'p4.music.126.net',
  ];

  static const Map<String, String> headers = <String, String>{
    'User-Agent': NeClientProfile.desktopUserAgent,
  };

  /// 只把NE自己的图片 CDN 提升为 HTTPS，第三方地址保持原样。
  static String? normalizeUrl(String? value) {
    final String? normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return normalized;
    }
    final String candidate = normalized.startsWith('//')
        ? 'https:$normalized'
        : normalized;
    final Uri? uri = Uri.tryParse(candidate);
    if (uri == null || !isMusicImageHost(uri.host)) {
      return normalized;
    }
    return uri.replace(scheme: 'https').toString();
  }

  /// 生成最多三个可互换的 CDN 请求地址，首项始终保留 API 返回的节点。
  ///
  /// NE图片路径在 p1/p3/p4 之间共享。固定候选上限可以在单节点拒绝或短暂
  /// 故障时恢复显示，同时避免无限重试和无界图片缓存键。
  static List<Uri> requestCandidates({
    required String url,
    required int decodeSize,
  }) {
    final String? normalized = normalizeUrl(url);
    final Uri? source = normalized == null ? null : Uri.tryParse(normalized);
    if (source == null) {
      return const <Uri>[];
    }
    if (!isMusicImageHost(source.host)) {
      return <Uri>[source];
    }

    final Uri resized = source.replace(
      scheme: 'https',
      queryParameters: <String, String>{
        ...source.queryParameters,
        'param': '${decodeSize}y$decodeSize',
      },
    );
    final List<String> hosts = <String>[
      resized.host.toLowerCase(),
      ...cdnHosts,
    ];
    final List<Uri> candidates = <Uri>[];
    for (final String host in hosts) {
      if (candidates.any((Uri candidate) => candidate.host == host)) {
        continue;
      }
      candidates.add(resized.replace(host: host));
      if (candidates.length == cdnHosts.length) {
        break;
      }
    }
    return List<Uri>.unmodifiable(candidates);
  }

  static bool isMusicImageHost(String host) {
    final String normalized = host.toLowerCase();
    return normalized == 'music.126.net' ||
        normalized.endsWith('.music.126.net');
  }
}
