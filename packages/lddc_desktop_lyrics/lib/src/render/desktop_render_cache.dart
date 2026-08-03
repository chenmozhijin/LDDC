import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'desktop_lyrics_perf_stats.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'desktop_render_models.dart';

/// 浮窗静态布局缓存键。
class DesktopFloatingLayoutCacheKey {
  const DesktopFloatingLayoutCacheKey({
    required this.planGeometryHash,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.fontFamily,
    required this.configuredFontSize,
    required this.devicePixelRatio,
    required this.fontSizeMode,
    required this.showFurigana,
  });

  final int planGeometryHash;
  final int viewportWidth;
  final int viewportHeight;
  final String fontFamily;
  final double configuredFontSize;
  final double devicePixelRatio;
  final DesktopFloatingFontSizeMode fontSizeMode;
  final bool showFurigana;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DesktopFloatingLayoutCacheKey &&
            planGeometryHash == other.planGeometryHash &&
            viewportWidth == other.viewportWidth &&
            viewportHeight == other.viewportHeight &&
            fontFamily == other.fontFamily &&
            configuredFontSize == other.configuredFontSize &&
            devicePixelRatio == other.devicePixelRatio &&
            fontSizeMode == other.fontSizeMode &&
            showFurigana == other.showFurigana;
  }

  @override
  int get hashCode => Object.hash(
    planGeometryHash,
    viewportWidth,
    viewportHeight,
    fontFamily,
    configuredFontSize,
    devicePixelRatio,
    fontSizeMode,
    showFurigana,
  );
}

/// 面板静态布局缓存键。
class DesktopPanelLayoutCacheKey {
  const DesktopPanelLayoutCacheKey({
    required this.planGeometryHash,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.fontFamily,
    required this.configuredFontSize,
    required this.layoutScale,
    required this.showFurigana,
  });

  final int planGeometryHash;
  final int viewportWidth;
  final int viewportHeight;
  final String fontFamily;
  final double configuredFontSize;
  final double layoutScale;
  final bool showFurigana;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DesktopPanelLayoutCacheKey &&
            planGeometryHash == other.planGeometryHash &&
            viewportWidth == other.viewportWidth &&
            viewportHeight == other.viewportHeight &&
            fontFamily == other.fontFamily &&
            configuredFontSize == other.configuredFontSize &&
            layoutScale == other.layoutScale &&
            showFurigana == other.showFurigana;
  }

  @override
  int get hashCode => Object.hash(
    planGeometryHash,
    viewportWidth,
    viewportHeight,
    fontFamily,
    configuredFontSize,
    layoutScale,
    showFurigana,
  );
}

/// 文本测量结果缓存值。
class DesktopMeasuredText {
  const DesktopMeasuredText({
    required this.width,
    required this.height,
    required this.ascent,
  });

  final double width;
  final double height;
  final double ascent;
}

/// 共享字形测量缓存。
class DesktopGlyphMeasureCache {
  DesktopGlyphMeasureCache({
    int measureEntryLimit = 4096,
    int measureByteLimit = 8 * 1024 * 1024,
    int charOffsetEntryLimit = 2048,
    int charOffsetByteLimit = 8 * 1024 * 1024,
  }) : _measureCache =
           _DesktopLruCache<_DesktopTextMeasureKey, DesktopMeasuredText>(
             name: 'glyphMeasure',
             maxEntries: measureEntryLimit,
             maxBytes: measureByteLimit,
           ),
       _charOffsetsCache =
           _DesktopLruCache<_DesktopCharOffsetKey, List<double>>(
             name: 'glyphCharOffsets',
             maxEntries: charOffsetEntryLimit,
             maxBytes: charOffsetByteLimit,
           );

  final _DesktopLruCache<_DesktopTextMeasureKey, DesktopMeasuredText>
  _measureCache;
  final _DesktopLruCache<_DesktopCharOffsetKey, List<double>> _charOffsetsCache;

  DesktopMeasuredText measureText({
    required String text,
    required TextStyle style,
  }) {
    final _DesktopTextMeasureKey key = _DesktopTextMeasureKey(
      text: text,
      style: style,
    );
    final DesktopMeasuredText? cached = _measureCache.read(key);
    if (cached != null) {
      return cached;
    }
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final List<LineMetrics> metrics = painter.computeLineMetrics();
    final LineMetrics? lineMetrics = metrics.isEmpty ? null : metrics.first;
    final DesktopMeasuredText value = DesktopMeasuredText(
      width: painter.width,
      height: painter.height,
      ascent: lineMetrics?.ascent ?? painter.height,
    );
    _measureCache.write(
      key,
      value,
      estimatedBytes: _estimateMeasuredTextBytes(text),
    );
    return value;
  }

  List<double> measureCharOffsets({
    required String text,
    required TextStyle style,
  }) {
    final _DesktopCharOffsetKey key = _DesktopCharOffsetKey(
      text: text,
      style: style,
    );
    final List<double>? cached = _charOffsetsCache.read(key);
    if (cached != null) {
      return cached;
    }
    final List<String> chars = text.characters.toList(growable: false);
    final List<double> offsets = <double>[0];
    double currentWidth = 0;
    for (final String char in chars) {
      currentWidth += measureText(text: char, style: style).width;
      offsets.add(currentWidth);
    }
    final List<double> value = List<double>.unmodifiable(offsets);
    _charOffsetsCache.write(
      key,
      value,
      estimatedBytes: _estimateCharOffsetsBytes(text, offsets.length),
    );
    return value;
  }

  void clear() {
    _measureCache.clear();
    _charOffsetsCache.clear();
  }

  void dispose() {
    clear();
  }
}

/// 单行静态测量缓存。
class DesktopLineMeasureCache {
  DesktopLineMeasureCache({
    int entryLimit = 1024,
    int byteLimit = 16 * 1024 * 1024,
  }) : _cache =
           _DesktopLruCache<
             _DesktopLineMeasureCacheKey,
             DesktopRenderMeasuredLine
           >(name: 'lineMeasure', maxEntries: entryLimit, maxBytes: byteLimit);

  final _DesktopLruCache<_DesktopLineMeasureCacheKey, DesktopRenderMeasuredLine>
  _cache;

  DesktopRenderMeasuredLine? read({
    required String text,
    required List<RubySpan> rubies,
    required TextStyle baseStyle,
    required bool reserveRubyHeight,
  }) {
    return _cache.read(
      _DesktopLineMeasureCacheKey(
        text: text,
        rubySignature: _buildRubySignature(rubies),
        baseStyle: baseStyle,
        reserveRubyHeight: reserveRubyHeight,
      ),
    );
  }

  void write({
    required String text,
    required List<RubySpan> rubies,
    required TextStyle baseStyle,
    required bool reserveRubyHeight,
    required DesktopRenderMeasuredLine measuredLine,
  }) {
    _cache.write(
      _DesktopLineMeasureCacheKey(
        text: text,
        rubySignature: _buildRubySignature(rubies),
        baseStyle: baseStyle,
        reserveRubyHeight: reserveRubyHeight,
      ),
      measuredLine,
      estimatedBytes: _estimateMeasuredLineBytes(text, measuredLine),
    );
  }

  void clear() {
    _cache.clear();
  }

  void dispose() {
    clear();
  }

  static String _buildRubySignature(List<RubySpan> rubies) {
    if (rubies.isEmpty) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    for (final RubySpan ruby in rubies) {
      buffer
        ..write(ruby.start)
        ..write(':')
        ..write(ruby.end)
        ..write(':')
        ..write(ruby.ruby)
        ..write(';');
    }
    return buffer.toString();
  }
}

/// 静态行 picture 缓存值。
class DesktopCachedLinePicture {
  DesktopCachedLinePicture({
    required this.image,
    required double padding,
    required int estimatedBytes,
  }) : padding = _requireNonNegativeFinite('padding', padding),
       estimatedBytes = _requirePositiveLimit('estimatedBytes', estimatedBytes);

  final ui.Image image;
  final double padding;
  final int estimatedBytes;
}

enum DesktopPictureCacheLane { floating, panel }

enum DesktopPictureHint { visible, protected, warm }

enum DesktopPictureCacheVariant { played, unplayed }

class DesktopPictureCacheBudget {
  const DesktopPictureCacheBudget({
    required this.softBudgetBytes,
    required this.hardBudgetBytes,
  });

  final int softBudgetBytes;
  final int hardBudgetBytes;
}

DesktopPictureCacheBudget resolveDesktopPictureCacheBudget({
  required DesktopPictureCacheLane lane,
  required int protectedFloorBytes,
}) {
  final int requiredBytes = _requireNonNegativeLimit(
    'protectedFloorBytes',
    protectedFloorBytes,
  );
  switch (lane) {
    case DesktopPictureCacheLane.floating:
      return DesktopPictureCacheBudget(
        softBudgetBytes: math.max(requiredBytes, 12 * 1024 * 1024),
        hardBudgetBytes: math.max(requiredBytes, 20 * 1024 * 1024),
      );
    case DesktopPictureCacheLane.panel:
      return DesktopPictureCacheBudget(
        softBudgetBytes: math.max(requiredBytes, 20 * 1024 * 1024),
        hardBudgetBytes: math.max(requiredBytes, 32 * 1024 * 1024),
      );
  }
}

class DesktopPictureCacheFrameContext {
  DesktopPictureCacheFrameContext({
    required this.frameId,
    required int softBudgetBytes,
    required int hardBudgetBytes,
  }) : softBudgetBytes = _requirePositiveLimit(
         'softBudgetBytes',
         softBudgetBytes,
       ),
       hardBudgetBytes = _validateHardBudget(
         softBudgetBytes: softBudgetBytes,
         hardBudgetBytes: hardBudgetBytes,
       );

  final int frameId;
  final int softBudgetBytes;
  final int hardBudgetBytes;
}

class DesktopLinePictureCacheFamilyKey {
  DesktopLinePictureCacheFamilyKey({
    required this.lineIdentity,
    required this.baseStyle,
    required this.rubyStyle,
    required this.themeSignature,
    required this.devicePixelRatio,
  }) : lineSignatureHash = _hashLineIdentity(lineIdentity);

  final Object lineIdentity;
  final int lineSignatureHash;
  final TextStyle baseStyle;
  final TextStyle rubyStyle;
  final int themeSignature;
  final double devicePixelRatio;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DesktopLinePictureCacheFamilyKey &&
            lineSignatureHash == other.lineSignatureHash &&
            _sameLineIdentity(lineIdentity, other.lineIdentity) &&
            baseStyle == other.baseStyle &&
            rubyStyle == other.rubyStyle &&
            themeSignature == other.themeSignature &&
            devicePixelRatio == other.devicePixelRatio;
  }

  @override
  int get hashCode => Object.hash(
    lineSignatureHash,
    baseStyle,
    rubyStyle,
    themeSignature,
    devicePixelRatio,
  );

  static int _hashLineIdentity(Object value) {
    if (value is DesktopRenderVisualLine) {
      int result = Object.hash(
        value.y,
        value.height,
        value.width,
        value.startX,
        value.visualLeft,
        value.visualRight,
        value.hasRubyLayout,
        value.tokens.length,
      );
      for (final DesktopRenderToken token in value.tokens) {
        result = Object.hash(
          result,
          token.type,
          token.text,
          token.rubyText,
          token.baseWidth,
          token.rubyWidth,
          token.height,
          token.ascent,
          token.x,
          token.leftOverhang,
          token.rightOverhang,
          Object.hashAll(token.charIndices),
          Object.hashAll(token.charOffsets),
        );
      }
      return result;
    }
    // 非视觉行对象只用于低频测试或未来扩展；真实 RenderView 会传入
    // DesktopRenderVisualLine 并走上面的结构签名。这里保留对象自身 hash，
    // 避免测试用 Object() 被相同 toString() 误合并成同一个 family。
    return Object.hash(value.runtimeType, value.hashCode);
  }

  static bool _sameLineIdentity(Object left, Object right) {
    if (identical(left, right)) {
      return true;
    }
    if (left is! DesktopRenderVisualLine || right is! DesktopRenderVisualLine) {
      return left == right;
    }
    if (left.y != right.y ||
        left.height != right.height ||
        left.width != right.width ||
        left.startX != right.startX ||
        left.visualLeft != right.visualLeft ||
        left.visualRight != right.visualRight ||
        left.hasRubyLayout != right.hasRubyLayout ||
        left.tokens.length != right.tokens.length) {
      return false;
    }
    for (int index = 0; index < left.tokens.length; index += 1) {
      final DesktopRenderToken leftToken = left.tokens[index];
      final DesktopRenderToken rightToken = right.tokens[index];
      if (leftToken.type != rightToken.type ||
          leftToken.text != rightToken.text ||
          leftToken.rubyText != rightToken.rubyText ||
          leftToken.baseWidth != rightToken.baseWidth ||
          leftToken.rubyWidth != rightToken.rubyWidth ||
          leftToken.height != rightToken.height ||
          leftToken.ascent != rightToken.ascent ||
          leftToken.x != rightToken.x ||
          leftToken.leftOverhang != rightToken.leftOverhang ||
          leftToken.rightOverhang != rightToken.rightOverhang ||
          !_sameList(leftToken.charIndices, rightToken.charIndices) ||
          !_sameList(leftToken.charOffsets, rightToken.charOffsets)) {
        return false;
      }
    }
    return true;
  }

  static bool _sameList<T>(List<T> left, List<T> right) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

/// 静态行 picture 缓存，对齐Python版的位图缓存思路。
class DesktopLinePictureCache {
  DesktopLinePictureCache({
    int entryLimit = 256,
    int byteLimit = 24 * 1024 * 1024,
  }) : _entryLimit = _requirePositiveLimit('entryLimit', entryLimit),
       _defaultSoftBudgetBytes = _requirePositiveLimit('byteLimit', byteLimit),
       _defaultHardBudgetBytes = math.max(
         _requirePositiveLimit('byteLimit', byteLimit),
         (byteLimit * 1.25).ceil(),
       );

  final int _entryLimit;
  final int _defaultSoftBudgetBytes;
  final int _defaultHardBudgetBytes;
  final Map<DesktopLinePictureCacheFamilyKey, _DesktopLinePictureFamilyEntry>
  _families =
      <DesktopLinePictureCacheFamilyKey, _DesktopLinePictureFamilyEntry>{};
  final Map<DesktopLinePictureCacheFamilyKey, _DesktopPictureFrameHintState>
  _pendingFrameHints =
      <DesktopLinePictureCacheFamilyKey, _DesktopPictureFrameHintState>{};

  DesktopPictureCacheFrameContext? _currentFrameContext;
  DesktopRenderGenerationKey? _boundGenerationKey;
  int _bytes = 0;
  int _pictureCount = 0;
  bool _disposed = false;

  void bindGeneration(DesktopRenderGenerationKey generationKey) {
    _ensureNotDisposed();
    if (_boundGenerationKey == generationKey) {
      return;
    }
    clear();
    _boundGenerationKey = generationKey;
  }

  DesktopLinePictureCacheFamilyKey buildFamilyKey({
    required Object lineIdentity,
    required TextStyle baseStyle,
    required TextStyle rubyStyle,
    required int themeSignature,
    required double devicePixelRatio,
  }) {
    return DesktopLinePictureCacheFamilyKey(
      lineIdentity: lineIdentity,
      baseStyle: baseStyle,
      rubyStyle: rubyStyle,
      themeSignature: themeSignature,
      devicePixelRatio: devicePixelRatio,
    );
  }

  T runFrame<T>(DesktopPictureCacheFrameContext context, T Function() action) {
    _ensureNotDisposed();
    _beginFrame(context);
    try {
      return action();
    } finally {
      _endFrame();
    }
  }

  void _beginFrame(DesktopPictureCacheFrameContext context) {
    _currentFrameContext = context;
    _pendingFrameHints.clear();
    for (final _DesktopLinePictureFamilyEntry family in _families.values) {
      family.beginFrame();
    }
  }

  void hintFamily(
    DesktopLinePictureCacheFamilyKey key,
    DesktopPictureHint hint, {
    int priorityClass = 0,
    double distanceToViewport = 0,
  }) {
    _ensureNotDisposed();
    final _DesktopPictureFrameHintState state = _pendingFrameHints.putIfAbsent(
      key,
      _DesktopPictureFrameHintState.new,
    );
    state.apply(
      hint,
      priorityClass: priorityClass,
      distanceToViewport: distanceToViewport,
    );
  }

  DesktopCachedLinePicture resolveLinePicture({
    required DesktopLinePictureCacheFamilyKey familyKey,
    required DesktopPictureCacheVariant variant,
    required DesktopCachedLinePicture Function() createPicture,
  }) {
    _ensureNotDisposed();
    final _DesktopLinePictureFamilyEntry family = _families.putIfAbsent(
      familyKey,
      () => _DesktopLinePictureFamilyEntry(key: familyKey),
    );
    _applyPendingHint(familyKey, family);
    final _DesktopCachedPictureVariant? cachedVariant =
        family.variants[variant];
    if (cachedVariant != null) {
      DesktopLyricsPerfStats.instance.bump('cacheHit');
      _touchVariant(family, cachedVariant, variant: variant);
      return cachedVariant.picture;
    }

    DesktopLyricsPerfStats.instance.bump('cacheMiss');
    final DesktopCachedLinePicture picture = createPicture();
    final _DesktopCachedPictureVariant createdVariant =
        _DesktopCachedPictureVariant(picture: picture);
    family.variants[variant] = createdVariant;
    family.totalBytes += picture.estimatedBytes;
    _bytes += picture.estimatedBytes;
    _pictureCount += 1;
    _touchVariant(family, createdVariant, variant: variant);
    _trimIfNeeded(targetBytes: _effectiveHardBudgetBytes);
    _recordCacheFootprint();
    return picture;
  }

  void _endFrame() {
    final DesktopPictureCacheFrameContext? context = _currentFrameContext;
    if (context == null) {
      return;
    }
    for (final _DesktopLinePictureFamilyEntry family in _families.values) {
      _applyPendingHint(family.key, family);
    }
    _trimIfNeeded(targetBytes: _effectiveSoftBudgetBytes);
    _pendingFrameHints.clear();
    _currentFrameContext = null;
    _recordCacheFootprint();
  }

  void clear() {
    for (final _DesktopLinePictureFamilyEntry family in _families.values) {
      for (final _DesktopCachedPictureVariant entry in family.variants.values) {
        _disposePicture(entry.picture);
      }
    }
    _families.clear();
    _pendingFrameHints.clear();
    _currentFrameContext = null;
    _bytes = 0;
    _pictureCount = 0;
    _recordCacheFootprint();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    clear();
    _boundGenerationKey = null;
    _disposed = true;
  }

  int get _effectiveSoftBudgetBytes =>
      _currentFrameContext?.softBudgetBytes ?? _defaultSoftBudgetBytes;

  int get _effectiveHardBudgetBytes =>
      _currentFrameContext?.hardBudgetBytes ?? _defaultHardBudgetBytes;

  void _applyPendingHint(
    DesktopLinePictureCacheFamilyKey key,
    _DesktopLinePictureFamilyEntry family,
  ) {
    final _DesktopPictureFrameHintState? pending = _pendingFrameHints[key];
    final DesktopPictureCacheFrameContext? context = _currentFrameContext;
    if (pending == null || context == null) {
      return;
    }
    family.priorityClass = math.max(
      family.priorityClass,
      pending.priorityClass,
    );
    family.distanceToViewport = math.min(
      family.distanceToViewport,
      pending.distanceToViewport,
    );
    if (pending.isVisible) {
      family.frameVisible = true;
      family.lastVisibleFrame = context.frameId;
    }
    if (pending.isProtected) {
      family.frameProtected = true;
      family.lastVisibleFrame = context.frameId;
      family.distanceToViewport = 0;
    }
    if (pending.isWarm) {
      family.frameWarm = true;
    }
  }

  void _touchVariant(
    _DesktopLinePictureFamilyEntry family,
    _DesktopCachedPictureVariant entry, {
    required DesktopPictureCacheVariant variant,
  }) {
    final DesktopPictureCacheFrameContext? context = _currentFrameContext;
    final int frameId = context?.frameId ?? 0;
    if (family.lastSeenFrame >= 0 && family.lastSeenFrame != frameId) {
      family.heat += 1;
      family.segment = _DesktopPictureCacheSegment.protectedReuse;
    }
    family.lastSeenFrame = frameId;
    entry.lastSeenFrame = frameId;
    entry.usedThisFrame = true;
    if (family.frameVisible || family.frameProtected) {
      entry.lastVisibleFrame = frameId;
      family.lastVisibleFrame = frameId;
    }
    if (family.frameProtected &&
        family.variants.containsKey(DesktopPictureCacheVariant.played) &&
        family.variants.containsKey(DesktopPictureCacheVariant.unplayed)) {
      family.priorityClass = math.max(family.priorityClass, 3);
    } else if (variant == DesktopPictureCacheVariant.played ||
        variant == DesktopPictureCacheVariant.unplayed) {
      family.priorityClass = math.max(family.priorityClass, 2);
    }
  }

  void _trimIfNeeded({required int targetBytes}) {
    while ((_bytes > targetBytes || _families.length > _entryLimit)) {
      final _DesktopPictureEvictionCandidate? candidate =
          _selectEvictionCandidate();
      if (candidate == null) {
        break;
      }
      _evictCandidate(candidate);
    }
    _recordCacheFootprint();
  }

  _DesktopPictureEvictionCandidate? _selectEvictionCandidate() {
    _DesktopPictureEvictionCandidate? best;
    for (final _DesktopLinePictureFamilyEntry family in _families.values) {
      if (family.frameProtected) {
        continue;
      }
      for (final MapEntry<
            DesktopPictureCacheVariant,
            _DesktopCachedPictureVariant
          >
          entry
          in family.variants.entries) {
        final _DesktopPictureEvictionCandidate? candidate =
            _buildVariantCandidate(family, entry.key, entry.value);
        if (_isBetterCandidate(candidate, best)) {
          best = candidate;
        }
      }
      final _DesktopPictureEvictionCandidate? familyCandidate =
          _buildFamilyCandidate(family);
      if (_isBetterCandidate(familyCandidate, best)) {
        best = familyCandidate;
      }
    }
    return best;
  }

  _DesktopPictureEvictionCandidate? _buildVariantCandidate(
    _DesktopLinePictureFamilyEntry family,
    DesktopPictureCacheVariant variant,
    _DesktopCachedPictureVariant entry,
  ) {
    if (entry.usedThisFrame) {
      return null;
    }
    final int stage = switch (family.segment) {
      _DesktopPictureCacheSegment.probation => family.frameWarm ? 2 : 0,
      _DesktopPictureCacheSegment.protectedReuse => 4,
    };
    return _DesktopPictureEvictionCandidate.variant(
      family: family,
      variant: variant,
      stage: stage,
      bytes: entry.picture.estimatedBytes,
    );
  }

  _DesktopPictureEvictionCandidate? _buildFamilyCandidate(
    _DesktopLinePictureFamilyEntry family,
  ) {
    if (family.variants.values.any(
      (_DesktopCachedPictureVariant entry) => entry.usedThisFrame,
    )) {
      return null;
    }
    final int stage = switch (family.segment) {
      _DesktopPictureCacheSegment.probation => family.frameWarm ? 3 : 1,
      _DesktopPictureCacheSegment.protectedReuse => family.frameWarm ? 3 : 5,
    };
    return _DesktopPictureEvictionCandidate.family(
      family: family,
      stage: stage,
      bytes: family.totalBytes,
    );
  }

  bool _isBetterCandidate(
    _DesktopPictureEvictionCandidate? candidate,
    _DesktopPictureEvictionCandidate? current,
  ) {
    if (candidate == null) {
      return false;
    }
    if (current == null) {
      return true;
    }
    if (candidate.stage != current.stage) {
      return candidate.stage < current.stage;
    }
    if (candidate.family.priorityClass != current.family.priorityClass) {
      return candidate.family.priorityClass < current.family.priorityClass;
    }
    if (candidate.family.distanceToViewport !=
        current.family.distanceToViewport) {
      return candidate.family.distanceToViewport >
          current.family.distanceToViewport;
    }
    if (candidate.family.lastVisibleFrame != current.family.lastVisibleFrame) {
      return candidate.family.lastVisibleFrame <
          current.family.lastVisibleFrame;
    }
    if (candidate.bytes != current.bytes) {
      return candidate.bytes > current.bytes;
    }
    return candidate.family.lastSeenFrame < current.family.lastSeenFrame;
  }

  void _evictCandidate(_DesktopPictureEvictionCandidate candidate) {
    if (candidate.variant case final DesktopPictureCacheVariant variant?) {
      final _DesktopCachedPictureVariant? entry = candidate.family.variants
          .remove(variant);
      if (entry == null) {
        return;
      }
      candidate.family.totalBytes -= entry.picture.estimatedBytes;
      _bytes -= entry.picture.estimatedBytes;
      _pictureCount -= 1;
      _disposePicture(entry.picture);
      DesktopLyricsPerfStats.instance
        ..bump('cacheEvict')
        ..bump('linePictureVariantEvict');
      if (candidate.family.variants.isEmpty) {
        _families.remove(candidate.family.key);
      }
      return;
    }
    final _DesktopLinePictureFamilyEntry? removedFamily = _families.remove(
      candidate.family.key,
    );
    if (removedFamily == null) {
      return;
    }
    int evictedPictures = 0;
    for (final _DesktopCachedPictureVariant entry
        in removedFamily.variants.values) {
      _bytes -= entry.picture.estimatedBytes;
      _pictureCount -= 1;
      evictedPictures += 1;
      _disposePicture(entry.picture);
    }
    DesktopLyricsPerfStats.instance
      ..bump('cacheEvict', evictedPictures)
      ..bump('linePictureFamilyEvict');
  }

  void _disposePicture(DesktopCachedLinePicture picture) {
    picture.image.dispose();
    DesktopLyricsPerfStats.instance.bump('pictureDispose');
  }

  void _recordCacheFootprint() {
    DesktopLyricsPerfStats.instance
      ..recordLatest('linePictureFamilies', _families.length)
      ..recordLatest('linePictureEntries', _pictureCount)
      ..recordLatest('linePictureBytes', _bytes)
      ..recordPeak('linePictureFamilies', _families.length)
      ..recordPeak('linePictureEntries', _pictureCount)
      ..recordPeak('linePictureBytes', _bytes);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('DesktopLinePictureCache 已释放');
    }
  }
}

class _DesktopLinePictureFamilyEntry {
  _DesktopLinePictureFamilyEntry({required this.key});

  final DesktopLinePictureCacheFamilyKey key;
  final Map<DesktopPictureCacheVariant, _DesktopCachedPictureVariant> variants =
      <DesktopPictureCacheVariant, _DesktopCachedPictureVariant>{};
  _DesktopPictureCacheSegment segment = _DesktopPictureCacheSegment.probation;
  int totalBytes = 0;
  int lastSeenFrame = -1;
  int lastVisibleFrame = -1;
  int heat = 0;
  int priorityClass = 0;
  double distanceToViewport = double.infinity;
  bool frameVisible = false;
  bool frameProtected = false;
  bool frameWarm = false;

  void beginFrame() {
    frameVisible = false;
    frameProtected = false;
    frameWarm = false;
    priorityClass = 0;
    distanceToViewport = double.infinity;
    for (final _DesktopCachedPictureVariant entry in variants.values) {
      entry.usedThisFrame = false;
    }
  }
}

class _DesktopCachedPictureVariant {
  _DesktopCachedPictureVariant({required this.picture});

  final DesktopCachedLinePicture picture;
  int lastSeenFrame = -1;
  int lastVisibleFrame = -1;
  bool usedThisFrame = false;
}

enum _DesktopPictureCacheSegment { probation, protectedReuse }

class _DesktopPictureFrameHintState {
  bool isVisible = false;
  bool isProtected = false;
  bool isWarm = false;
  int priorityClass = 0;
  double distanceToViewport = double.infinity;

  void apply(
    DesktopPictureHint hint, {
    required int priorityClass,
    required double distanceToViewport,
  }) {
    switch (hint) {
      case DesktopPictureHint.visible:
        isVisible = true;
      case DesktopPictureHint.protected:
        isProtected = true;
      case DesktopPictureHint.warm:
        isWarm = true;
    }
    this.priorityClass = math.max(this.priorityClass, priorityClass);
    this.distanceToViewport = math.min(
      this.distanceToViewport,
      distanceToViewport,
    );
  }
}

class _DesktopPictureEvictionCandidate {
  const _DesktopPictureEvictionCandidate._({
    required this.family,
    required this.variant,
    required this.stage,
    required this.bytes,
  });

  const _DesktopPictureEvictionCandidate.family({
    required _DesktopLinePictureFamilyEntry family,
    required int stage,
    required int bytes,
  }) : this._(family: family, variant: null, stage: stage, bytes: bytes);

  const _DesktopPictureEvictionCandidate.variant({
    required _DesktopLinePictureFamilyEntry family,
    required DesktopPictureCacheVariant variant,
    required int stage,
    required int bytes,
  }) : this._(family: family, variant: variant, stage: stage, bytes: bytes);

  final _DesktopLinePictureFamilyEntry family;
  final DesktopPictureCacheVariant? variant;
  final int stage;
  final int bytes;
}

class _DesktopLruCache<K, V> {
  _DesktopLruCache({
    required this.name,
    required int maxEntries,
    required int maxBytes,
    this.disposeValue,
  }) : maxEntries = _requirePositiveLimit('maxEntries', maxEntries),
       maxBytes = _requirePositiveLimit('maxBytes', maxBytes);

  final String name;
  final int maxEntries;
  final int maxBytes;
  final void Function(V value)? disposeValue;
  final LinkedHashMap<K, _DesktopCacheEntry<V>> _entries =
      LinkedHashMap<K, _DesktopCacheEntry<V>>();
  int _bytes = 0;

  V? read(K key) {
    final _DesktopCacheEntry<V>? entry = _entries.remove(key);
    if (entry == null) {
      DesktopLyricsPerfStats.instance.bump('cacheMiss');
      return null;
    }
    _entries[key] = entry;
    DesktopLyricsPerfStats.instance.bump('cacheHit');
    return entry.value;
  }

  void write(K key, V value, {required int estimatedBytes}) {
    final int resolvedBytes = _requirePositiveLimit(
      'estimatedBytes',
      estimatedBytes,
    );
    final _DesktopCacheEntry<V>? previous = _entries.remove(key);
    if (previous != null) {
      _bytes -= previous.estimatedBytes;
      disposeValue?.call(previous.value);
    }
    _entries[key] = _DesktopCacheEntry<V>(
      value: value,
      estimatedBytes: resolvedBytes,
    );
    _bytes += resolvedBytes;
    _evictIfNeeded();
    DesktopLyricsPerfStats.instance
      ..recordPeak('${name}Entries', _entries.length)
      ..recordPeak('${name}Bytes', _bytes);
  }

  void clear() {
    for (final _DesktopCacheEntry<V> entry in _entries.values) {
      disposeValue?.call(entry.value);
    }
    _entries.clear();
    _bytes = 0;
  }

  void _evictIfNeeded() {
    while (_entries.length > maxEntries || _bytes > maxBytes) {
      if (_entries.isEmpty) {
        break;
      }
      final K eldestKey = _entries.keys.first;
      final _DesktopCacheEntry<V> eldest = _entries.remove(eldestKey)!;
      _bytes -= eldest.estimatedBytes;
      disposeValue?.call(eldest.value);
      DesktopLyricsPerfStats.instance.bump('cacheEvict');
    }
  }
}

class _DesktopCacheEntry<V> {
  const _DesktopCacheEntry({required this.value, required this.estimatedBytes});

  final V value;
  final int estimatedBytes;
}

class _DesktopTextMeasureKey {
  const _DesktopTextMeasureKey({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _DesktopTextMeasureKey &&
            text == other.text &&
            style == other.style;
  }

  @override
  int get hashCode => Object.hash(text, style);
}

class _DesktopCharOffsetKey {
  const _DesktopCharOffsetKey({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _DesktopCharOffsetKey &&
            text == other.text &&
            style == other.style;
  }

  @override
  int get hashCode => Object.hash(text, style);
}

class _DesktopLineMeasureCacheKey {
  const _DesktopLineMeasureCacheKey({
    required this.text,
    required this.rubySignature,
    required this.baseStyle,
    required this.reserveRubyHeight,
  });

  final String text;
  final String rubySignature;
  final TextStyle baseStyle;
  final bool reserveRubyHeight;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _DesktopLineMeasureCacheKey &&
            text == other.text &&
            rubySignature == other.rubySignature &&
            baseStyle == other.baseStyle &&
            reserveRubyHeight == other.reserveRubyHeight;
  }

  @override
  int get hashCode =>
      Object.hash(text, rubySignature, baseStyle, reserveRubyHeight);
}

int _estimateMeasuredTextBytes(String text) => 96 + text.length * 2;

int _estimateCharOffsetsBytes(String text, int offsetCount) =>
    96 + text.length * 2 + offsetCount * 8;

int _estimateMeasuredLineBytes(
  String text,
  DesktopRenderMeasuredLine measuredLine,
) {
  return 256 +
      text.length * 2 +
      measuredLine.segments.length * 96 +
      measuredLine.visualLine.tokens.length * 96;
}

int _requirePositiveLimit(String name, int value) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, '必须大于 0');
  }
  return value;
}

int _requireNonNegativeLimit(String name, int value) {
  if (value < 0) {
    throw ArgumentError.value(value, name, '不能小于 0');
  }
  return value;
}

double _requireNonNegativeFinite(String name, double value) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, '必须是非负有限数值');
  }
  return value;
}

int _validateHardBudget({
  required int softBudgetBytes,
  required int hardBudgetBytes,
}) {
  final int resolvedHardBudget = _requirePositiveLimit(
    'hardBudgetBytes',
    hardBudgetBytes,
  );
  if (resolvedHardBudget < softBudgetBytes) {
    throw ArgumentError.value(
      hardBudgetBytes,
      'hardBudgetBytes',
      '不能小于 softBudgetBytes',
    );
  }
  return resolvedHardBudget;
}
