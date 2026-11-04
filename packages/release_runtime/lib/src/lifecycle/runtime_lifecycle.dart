// packages/release_runtime/lib/src/lifecycle/runtime_lifecycle.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'dart:async';

/// Lifecycle states of [ReleaseMcpRuntime].
///
/// `disabled` is the only state a freshly constructed runtime can be in: a
/// listener is never bound by construction, by import, or by `main()`.
enum ReleaseRuntimeState {
  /// Not serving; no transport is bound.
  disabled('disabled'),

  /// A start was requested and the transport has not answered yet.
  starting('starting'),

  /// Serving; the transport reported its endpoint (or accepted the handoff).
  running('running'),

  /// A stop was requested and the transport is shutting down.
  stopping('stopping'),

  /// The last transition failed. Inspect `errorCode`, then stop or retry.
  error('error');

  const ReleaseRuntimeState(this.wireName);

  /// Stable wire name.
  final String wireName;

  /// True for `starting` and `stopping`: a transition is in flight.
  bool get isTransitional =>
      this == ReleaseRuntimeState.starting ||
      this == ReleaseRuntimeState.stopping;

  /// True only for `running`.
  bool get isServing => this == ReleaseRuntimeState.running;
}

/// The state machine behind [ReleaseMcpRuntime].
///
/// Owns the current state, the last error code, and the state broadcast
/// stream. Transitions are checked against an explicit table; an illegal
/// transition is a programming error and throws [StateError] rather than
/// silently corrupting state.
final class ReleaseRuntimeLifecycle {
  ReleaseRuntimeLifecycle();

  /// Allowed transitions. Everything else is rejected.
  ///
  /// `running -> disabled` and `error -> disabled` exist for `dispose()`,
  /// which must be able to tear down from any non-disabled state.
  static const Map<ReleaseRuntimeState, Set<ReleaseRuntimeState>>
  allowedTransitions = <ReleaseRuntimeState, Set<ReleaseRuntimeState>>{
    ReleaseRuntimeState.disabled: <ReleaseRuntimeState>{
      ReleaseRuntimeState.starting,
    },
    ReleaseRuntimeState.starting: <ReleaseRuntimeState>{
      ReleaseRuntimeState.running,
      ReleaseRuntimeState.stopping,
      ReleaseRuntimeState.error,
    },
    ReleaseRuntimeState.running: <ReleaseRuntimeState>{
      ReleaseRuntimeState.stopping,
      ReleaseRuntimeState.error,
      ReleaseRuntimeState.disabled,
    },
    ReleaseRuntimeState.stopping: <ReleaseRuntimeState>{
      ReleaseRuntimeState.disabled,
      ReleaseRuntimeState.error,
    },
    ReleaseRuntimeState.error: <ReleaseRuntimeState>{
      ReleaseRuntimeState.disabled,
      ReleaseRuntimeState.starting,
      ReleaseRuntimeState.stopping,
    },
  };

  final StreamController<ReleaseRuntimeState> _changes =
      StreamController<ReleaseRuntimeState>.broadcast();

  ReleaseRuntimeState _state = ReleaseRuntimeState.disabled;
  String? _errorCode;
  bool _closed = false;

  /// Current state.
  ReleaseRuntimeState get state => _state;

  /// Error code recorded by the last failure, cleared by a successful
  /// transition.
  String? get errorCode => _errorCode;

  /// Broadcast stream of state changes. Emits the new state after it is
  /// committed, so `state` already reflects the emitted value.
  Stream<ReleaseRuntimeState> get changes => _changes.stream;

  /// True once [close] has run.
  bool get isClosed => _closed;

  /// Whether [next] is legal from the current state.
  bool canTransitionTo(ReleaseRuntimeState next) =>
      allowedTransitions[_state]?.contains(next) ?? false;

  /// Commits [next].
  ///
  /// Throws [StateError] when the transition is not in
  /// [allowedTransitions], or when this lifecycle is already closed.
  void transitionTo(ReleaseRuntimeState next, {String? errorCode}) {
    if (_closed) {
      throw StateError('release runtime lifecycle is closed');
    }
    if (!canTransitionTo(next)) {
      throw StateError(
        'illegal release runtime transition: '
        '${_state.wireName} -> ${next.wireName}',
      );
    }

    _state = next;
    _errorCode = next == ReleaseRuntimeState.error ? errorCode : null;
    _changes.add(next);
  }

  /// Records a failure: transitions to `error` and stores [errorCode].
  void fail(String errorCode) {
    transitionTo(ReleaseRuntimeState.error, errorCode: errorCode);
  }

  /// Closes the broadcast stream. Idempotent.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _changes.close();
  }
}
