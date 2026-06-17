import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Extension on [BuildContext] providing a guarded [pop] that is a no-op
/// when the navigation stack is empty. Prevents silent failures on
/// screens reached via [context.go()].
extension SafePop on BuildContext {
  void safePop([Object? result]) {
    if (canPop()) {
      pop(result);
    }
  }
}
