import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Generic [Notifier] that holds a single value, replacing [StateProvider].
///
/// Read: `ref.watch(provider)`.
/// Write: `ref.read(provider.notifier).state = value`.
class StateHolder<T> extends Notifier<T> {
  StateHolder(this._create);
  final T Function(Ref ref) _create;
  @override
  T build() => _create(ref);

  /// Mutate the current state via an updater function.
  /// Equivalent to `StateController.update()` from riverpod legacy.
  void update(T Function(T) updater) {
    state = updater(state);
  }
}

/// Family variant of [StateHolder] for [StateProvider.family] replacements.
class FamilyStateHolder<T, A> extends Notifier<T> {
  FamilyStateHolder(this._create, this._arg);
  final T Function(A arg) _create;
  final A _arg;
  @override
  T build() => _create(_arg);
}
