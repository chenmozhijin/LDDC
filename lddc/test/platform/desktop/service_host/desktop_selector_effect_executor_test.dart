import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_selector_context_builder.dart';
import '../../../support/desktop_service_host_exports.dart';
import '../../../support/desktop_service_test_support.dart';

void main() {
  test('选择器关键词保留有效歌手，并过滤过长合作名单', () {
    SongInfo song({required String artist, String? title}) {
      return SongInfo(
        source: Source.local,
        title: title,
        artist: SongArtist(<String>[artist]),
        album: '',
      );
    }

    expect(
      buildDesktopSelectorKeyword(song(artist: 'Artist', title: 'Song')),
      'Artist - Song',
    );
    expect(
      buildDesktopSelectorKeyword(
        song(artist: 'A very long collaboration', title: 'Song'),
      ),
      'Song',
    );
    expect(buildDesktopSelectorKeyword(song(artist: 'Artist')), 'Artist');
    expect(buildDesktopSelectorKeyword(null), isNull);
  });

  group('DesktopSelectorEffectExecutor', () {
    test('to_select(false) 语义会显示窗口并注入上下文', () async {
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final DesktopSelectorEffectExecutor executor =
          DesktopSelectorEffectExecutor(
            windowBackend: _FakeWindowBackend(selectorHost: selectorHost),
          );

      await executor.execute(
        DesktopRefreshSelectorEffect(
          instanceId: 3,
          context: DesktopSelectorWindowContext(
            keyword: 'Artist - Song',
            langs: <String>['orig', 'ts'],
            offsetMs: 120,
          ),
          onlyIfVisible: false,
        ),
      );

      expect(selectorHost.calls, <String>['show:3:Artist - Song']);
    });

    test('to_select(true) 语义只刷新已显示窗口', () async {
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final DesktopSelectorEffectExecutor executor =
          DesktopSelectorEffectExecutor(
            windowBackend: _FakeWindowBackend(selectorHost: selectorHost),
          );

      await executor.execute(
        DesktopRefreshSelectorEffect(
          instanceId: 5,
          context: DesktopSelectorWindowContext(
            keyword: 'Artist - Song',
            langs: <String>['orig'],
            offsetMs: 0,
          ),
          onlyIfVisible: true,
        ),
      );

      expect(selectorHost.calls, <String>['refresh:5:Artist - Song']);
    });

    test('遇到非选择器 effect 时直接忽略', () async {
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final DesktopSelectorEffectExecutor executor =
          DesktopSelectorEffectExecutor(
            windowBackend: _FakeWindowBackend(selectorHost: selectorHost),
          );

      await executor.execute(
        const DesktopClearTaskEffect(taskKey: 'auto_fetch'),
      );

      expect(selectorHost.calls, isEmpty);
    });

    test('跨批次调用按实例串行，并以最新上下文保留显示请求', () async {
      final _BlockingSelectorHost selectorHost = _BlockingSelectorHost();
      final DesktopSelectorEffectExecutor executor =
          DesktopSelectorEffectExecutor(
            windowBackend: _FakeWindowBackend(selectorHost: selectorHost),
          );

      final Future<void> first = executor.execute(
        DesktopRefreshSelectorEffect(
          instanceId: 8,
          context: DesktopSelectorWindowContext(
            keyword: 'first',
            langs: const <String>['orig'],
            offsetMs: 0,
          ),
          onlyIfVisible: true,
        ),
      );
      await waitForCondition(() => selectorHost.calls.isNotEmpty);

      final Future<void> second = executor.execute(
        DesktopRefreshSelectorEffect(
          instanceId: 8,
          context: DesktopSelectorWindowContext(
            keyword: 'second',
            langs: const <String>['orig'],
            offsetMs: 0,
          ),
          onlyIfVisible: false,
        ),
      );
      final Future<void> third = executor.execute(
        DesktopRefreshSelectorEffect(
          instanceId: 8,
          context: DesktopSelectorWindowContext(
            keyword: 'latest',
            langs: const <String>['orig'],
            offsetMs: 0,
          ),
          onlyIfVisible: true,
        ),
      );

      expect(selectorHost.calls, <String>['refresh:8:first']);
      selectorHost.completeFirstCall();
      await Future.wait(<Future<void>>[first, second, third]);

      expect(selectorHost.calls, <String>['refresh:8:first', 'show:8:latest']);
    });

    test('销毁会等待正在执行的调用，并丢弃尚未发送的旧上下文', () async {
      final _BlockingSelectorHost selectorHost = _BlockingSelectorHost();
      final DesktopSelectorEffectExecutor executor =
          DesktopSelectorEffectExecutor(
            windowBackend: _FakeWindowBackend(selectorHost: selectorHost),
          );

      final Future<void> first = executor.execute(
        DesktopRefreshSelectorEffect(
          instanceId: 9,
          context: DesktopSelectorWindowContext(
            keyword: 'running',
            langs: const <String>['orig'],
            offsetMs: 0,
          ),
          onlyIfVisible: true,
        ),
      );
      await waitForCondition(() => selectorHost.calls.isNotEmpty);
      final Future<void> pending = executor.execute(
        DesktopRefreshSelectorEffect(
          instanceId: 9,
          context: DesktopSelectorWindowContext(
            keyword: 'stale',
            langs: const <String>['orig'],
            offsetMs: 0,
          ),
          onlyIfVisible: false,
        ),
      );
      final Future<void> destroy = executor.destroyInstance(9);

      expect(selectorHost.calls, <String>['refresh:9:running']);
      selectorHost.completeFirstCall();
      await Future.wait(<Future<void>>[first, pending, destroy]);

      expect(selectorHost.calls, <String>['refresh:9:running', 'destroy:9']);
    });
  });
}

class _FakeWindowBackend implements DesktopWindowBackend {
  _FakeWindowBackend({required this.selectorHost});

  @override
  final DesktopFloatingWindowHostPort floatingHost =
      const DesktopNoopFloatingWindowHost();

  @override
  final _FakeSelectorHost selectorHost;

  @override
  final DesktopPanelWindowHostPort panelHost =
      const DesktopNoopPanelWindowHost();
}

class _FakeSelectorHost implements DesktopSelectorWindowHostPort {
  final List<String> calls = <String>[];

  @override
  void setIntentHandler(DesktopSelectorWindowIntentHandler? handler) {}

  @override
  Future<void> publishConfigRevision({required int revision}) async {
    calls.add('config:$revision');
  }

  @override
  Future<void> destroySelectorWindow({required int instanceId}) async {}

  @override
  Future<void> ensureSelectorWindow({required int instanceId}) async {}

  @override
  Future<void> hideSelectorWindow({required int instanceId}) async {
    calls.add('hide:$instanceId');
  }

  @override
  Future<void> refreshSelectorContext({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  }) async {
    calls.add('refresh:$instanceId:${context.keyword}');
  }

  @override
  Future<void> showSelectorWindow({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  }) async {
    calls.add('show:$instanceId:${context.keyword}');
  }
}

class _BlockingSelectorHost extends _FakeSelectorHost {
  final Completer<void> _firstCallCompleter = Completer<void>();
  bool _firstCallSeen = false;

  void completeFirstCall() {
    if (!_firstCallCompleter.isCompleted) {
      _firstCallCompleter.complete();
    }
  }

  @override
  Future<void> destroySelectorWindow({required int instanceId}) async {
    calls.add('destroy:$instanceId');
  }

  @override
  Future<void> refreshSelectorContext({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  }) async {
    calls.add('refresh:$instanceId:${context.keyword}');
    if (!_firstCallSeen) {
      _firstCallSeen = true;
      await _firstCallCompleter.future;
    }
  }
}
