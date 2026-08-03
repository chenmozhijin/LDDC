import 'package:flutter/material.dart';

import '../../ui/search_ui_strings.dart';
import '../search_workflow_controller.dart';
import '../search_workflow_state.dart';

bool isSearchSourceFailureNotice(SearchNoticeCode code) {
  return code == SearchNoticeCode.searchPartialSourcesFailed ||
      code == SearchNoticeCode.searchAllSourcesFailed ||
      code == SearchNoticeCode.searchLoadMoreFailed;
}

Future<void> showSearchSourceFailuresDialog({
  required BuildContext context,
  required SearchWorkflowController controller,
  required SearchUiStrings strings,
}) async {
  final List<SearchSourceFailure> failures = List<SearchSourceFailure>.of(
    controller.state.sourceFailures,
  );
  if (failures.isEmpty) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(strings.text(SearchUiTextKey.sourceFailureDetailsTitle)),
        content: SizedBox(
          // AlertDialog 会查询内容的固有宽度；直接放 shrinkWrap ListView 会触发
          // viewport 固有尺寸断言。固定一个会被父约束自动收窄的宽度后，列表只
          // 负责有界高度滚动，不需要实例化全部错误项来测量宽度。
          width: 560,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SelectionArea(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: failures.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final SearchSourceFailure failure = failures[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.error_outline_rounded),
                    title: Text(strings.sourceLabel(failure.source)),
                    subtitle: Text(
                      '${_failureKindText(strings, failure.kind)}\n'
                      '${failure.detail}',
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              MaterialLocalizations.of(dialogContext).closeButtonLabel,
            ),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              controller.retryFailedSources();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(strings.text(SearchUiTextKey.retry)),
          ),
        ],
      );
    },
  );
}

String _failureKindText(SearchUiStrings strings, SearchSourceFailureKind kind) {
  return strings.text(switch (kind) {
    SearchSourceFailureKind.request => SearchUiTextKey.sourceFailureRequest,
    SearchSourceFailureKind.timeout => SearchUiTextKey.sourceFailureTimeout,
    SearchSourceFailureKind.parameters =>
      SearchUiTextKey.sourceFailureParameters,
    SearchSourceFailureKind.unsupported =>
      SearchUiTextKey.sourceFailureUnsupported,
    SearchSourceFailureKind.unknown => SearchUiTextKey.sourceFailureUnknown,
  });
}
