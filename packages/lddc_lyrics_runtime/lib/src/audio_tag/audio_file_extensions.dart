import 'dart:collection';

/// 以 TagLib `FileRef::defaultFileExtensions` 为基线，排除视频与模块音乐扩展。
const List<String> audioFileExtensions = <String>[
  '3g2',
  'aac',
  'afc',
  'aif',
  'aifc',
  'aiff',
  'ape',
  'asf',
  'dff',
  'dsdiff',
  'dsf',
  'flac',
  'm4a',
  'm4b',
  'm4p',
  'm4r',
  'mka',
  'mp2',
  'mp3',
  'mp4',
  'mpc',
  'oga',
  'ogg',
  'opus',
  'shn',
  'spx',
  'tta',
  'wav',
  'wma',
  'wv',
];

/// 提供只读集合视图，供扫描与快速判定复用。
final Set<String> audioFileExtensionSet = UnmodifiableSetView<String>(
  Set<String>.from(audioFileExtensions),
);
