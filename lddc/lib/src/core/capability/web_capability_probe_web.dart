import 'dart:js_interop';

import 'package:dart_taglib/dart_taglib.dart';

import 'web_capability_probe.dart';

@JS('showOpenFilePicker')
external JSAny? get _showOpenFilePicker;

@JS('showSaveFilePicker')
external JSAny? get _showSaveFilePicker;

Future<WebCapabilitySnapshot> probeWebCapabilities() async {
  // File System Access 需要打开与保存入口都存在，单独存在一个 API 时不能承诺
  // 完整读写歌词文件能力。TagLib WASM 则以 dart_taglib 已安装 bridge 为准，
  // 不在启动期主动加载大 wasm，避免首页初始化阻塞和额外内存峰值。
  return WebCapabilitySnapshot(
    fileSystemAccess:
        _showOpenFilePicker != null && _showSaveFilePicker != null,
    taglibWasmReady: hasTaglibWasmBridge(),
  );
}
