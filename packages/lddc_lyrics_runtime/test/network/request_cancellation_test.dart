import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('父令牌取消会幂等传播到子令牌', () async {
    final RequestCancellationToken parent = RequestCancellationToken();
    final RequestCancellationToken child = parent.child();
    int notifications = 0;
    child.addCancellationListener(() => notifications += 1);

    parent
      ..cancel()
      ..cancel();
    await child.whenCancelled;

    expect(parent.isCancelled, isTrue);
    expect(child.isCancelled, isTrue);
    expect(notifications, 1);
    expect(child.throwIfCancelled, throwsA(isA<RequestCancelledException>()));
    child.dispose();
    parent.dispose();
  });

  test('子令牌 dispose 后不再保留父监听', () {
    final RequestCancellationToken parent = RequestCancellationToken();
    final RequestCancellationToken child = parent.child();

    child.dispose();
    parent.cancel();

    expect(child.isCancelled, isFalse);
    parent.dispose();
  });

  test('runWith 只在当前异步调用链暴露令牌', () async {
    final RequestCancellationToken token = RequestCancellationToken();

    expect(RequestCancellationToken.current, isNull);
    await RequestCancellationToken.runWith<void>(token, () async {
      expect(RequestCancellationToken.current, same(token));
      await Future<void>.delayed(Duration.zero);
      expect(RequestCancellationToken.current, same(token));
    });
    expect(RequestCancellationToken.current, isNull);
    token.dispose();
  });
}
