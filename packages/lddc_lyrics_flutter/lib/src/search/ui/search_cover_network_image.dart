import 'package:flutter/material.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart'
    show NeCoverRequestPolicy;

/// 搜索结果封面的有界网络图片实现。
///
/// 这个组件只处理图片传输身份和解码边界，具体占位图仍由结果行决定，
/// 因此不会把来源展示规则与网络协议耦合在一起。
class SearchCoverNetworkImage extends StatefulWidget {
  const SearchCoverNetworkImage({
    required this.url,
    required this.source,
    required this.errorFallback,
    super.key,
  });

  static const double logicalSize = 50;
  static const int minimumDecodeSize = 50;
  static const int maximumDecodeSize = 200;

  final String url;
  final Source source;
  final Widget errorFallback;

  @override
  State<SearchCoverNetworkImage> createState() =>
      _SearchCoverNetworkImageState();
}

class _SearchCoverNetworkImageState extends State<SearchCoverNetworkImage> {
  int _candidateIndex = 0;
  String? _requestKey;

  @override
  Widget build(BuildContext context) {
    final int decodeSize =
        (SearchCoverNetworkImage.logicalSize *
                MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(
              SearchCoverNetworkImage.minimumDecodeSize,
              SearchCoverNetworkImage.maximumDecodeSize,
            );
    final List<Uri> candidates = widget.source == Source.ne
        ? NeCoverRequestPolicy.requestCandidates(
            url: widget.url,
            decodeSize: decodeSize,
          )
        : <Uri>[if (Uri.tryParse(widget.url) case final Uri uri) uri];
    final String requestKey =
        '${widget.source.value}|${widget.url}|$decodeSize';
    if (_requestKey != requestKey) {
      _requestKey = requestKey;
      _candidateIndex = 0;
    }
    if (candidates.isEmpty) {
      return widget.errorFallback;
    }
    final int candidateIndex = _candidateIndex.clamp(0, candidates.length - 1);
    return Image.network(
      candidates[candidateIndex].toString(),
      // p1 CDN 会拒绝 Dart 默认 UA。请求头严格限制在NE来源，避免
      // 改变其他歌词源的缓存键、鉴权语义或 CDN 行为。
      headers: widget.source == Source.ne ? NeCoverRequestPolicy.headers : null,
      width: SearchCoverNetworkImage.logicalSize,
      height: SearchCoverNetworkImage.logicalSize,
      cacheWidth: decodeSize,
      cacheHeight: decodeSize,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) {
        _advanceCandidate(
          requestKey: requestKey,
          failedIndex: candidateIndex,
          candidateCount: candidates.length,
        );
        return widget.errorFallback;
      },
    );
  }

  void _advanceCandidate({
    required String requestKey,
    required int failedIndex,
    required int candidateCount,
  }) {
    if (requestKey != _requestKey ||
        failedIndex != _candidateIndex ||
        failedIndex + 1 >= candidateCount) {
      return;
    }
    // Image.errorBuilder 在布局阶段也可能被调用，延后一帧切换候选可以避免
    // build 期间 setState，同时每个失败节点只推进一次。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _requestKey != requestKey ||
          _candidateIndex != failedIndex) {
        return;
      }
      setState(() {
        _candidateIndex = failedIndex + 1;
      });
    });
  }
}
