import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell_route.dart';

final Provider<ValueNotifier<AppShellRoute>> appShellRouteListenableProvider =
    Provider<ValueNotifier<AppShellRoute>>((Ref ref) {
      final ValueNotifier<AppShellRoute> notifier =
          ValueNotifier<AppShellRoute>(AppShellRoute.search);
      ref.onDispose(notifier.dispose);
      return notifier;
    });
