import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import '../support/search_workflow_test_support.dart';

void main() {
  test('目录选择成功、取消和不支持均产生明确状态', () async {
    final _ScriptedFilePicker picker = _ScriptedFilePicker();
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController(filePicker: picker);
    addTearDown(controller.dispose);

    picker.directoryResult = () async => '  C:/Lyrics  ';
    await controller.selectSaveDirectory();
    expect(controller.state.saveDirectoryPath, 'C:/Lyrics');
    expect(picker.lastInitialDirectory, isNull);

    picker.directoryResult = () async => null;
    await controller.selectSaveDirectory();
    expect(controller.state.saveDirectoryPath, 'C:/Lyrics');
    expect(picker.lastInitialDirectory, 'C:/Lyrics');

    picker.directoryResult = () async => throw UnsupportedError('directory');
    await controller.selectSaveDirectory();
    expect(
      controller.state.notice?.code,
      SearchNoticeCode.directoryPickerUnsupported,
    );
  });

  test('音频选择取消、不支持和空拖放路径使用稳定通知码', () async {
    final _ScriptedFilePicker picker = _ScriptedFilePicker();
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController(filePicker: picker);
    addTearDown(controller.dispose);

    picker.audioResult = () async => null;
    await controller.openSongFileForSearch();
    expect(
      controller.state.notice?.code,
      SearchNoticeCode.selectedSongUnavailable,
    );
    expect(picker.releaseCount, 0);
    controller.dismissNotice();

    picker.audioResult = () async => throw UnsupportedError('audio');
    await controller.openSongFileForSearch();
    expect(
      controller.state.notice?.code,
      SearchNoticeCode.filePickerUnsupported,
    );
    expect(picker.releaseCount, 0);
    controller.dismissNotice();

    await controller.openDroppedSongFile('   ');
    expect(
      controller.state.notice?.code,
      SearchNoticeCode.droppedSongUnavailable,
    );
  });
}

final class _ScriptedFilePicker extends Fake implements AppFilePicker {
  Future<String?> Function() directoryResult = () async => null;
  Future<PickedAudioFileHandle?> Function() audioResult = () async => null;
  String? lastInitialDirectory;
  int releaseCount = 0;

  @override
  Future<String?> pickDirectory({String? initialDirectory}) {
    lastInitialDirectory = initialDirectory;
    return directoryResult();
  }

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({String? initialDirectory}) {
    lastInitialDirectory = initialDirectory;
    return audioResult();
  }

  @override
  Future<void> releaseAudioFile(PickedAudioFileHandle file) async {
    releaseCount += 1;
  }
}
