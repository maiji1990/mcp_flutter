// packages/release_runtime/test/lifecycle/runtime_lifecycle_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseRuntimeLifecycle', () {
    test('starts disabled with no error', () {
      final lifecycle = ReleaseRuntimeLifecycle();

      expect(lifecycle.state, ReleaseRuntimeState.disabled);
      expect(lifecycle.errorCode, isNull);
      expect(lifecycle.isClosed, isFalse);
    });

    test('walks the happy path disabled -> starting -> running -> stopping -> '
        'disabled', () {
      final lifecycle = ReleaseRuntimeLifecycle();

      lifecycle.transitionTo(ReleaseRuntimeState.starting);
      lifecycle.transitionTo(ReleaseRuntimeState.running);
      lifecycle.transitionTo(ReleaseRuntimeState.stopping);
      lifecycle.transitionTo(ReleaseRuntimeState.disabled);

      expect(lifecycle.state, ReleaseRuntimeState.disabled);
      expect(lifecycle.errorCode, isNull);
    });

    test('rejects illegal transitions instead of corrupting state', () {
      final lifecycle = ReleaseRuntimeLifecycle();

      expect(
        () => lifecycle.transitionTo(ReleaseRuntimeState.running),
        throwsStateError,
      );
      expect(lifecycle.state, ReleaseRuntimeState.disabled);

      lifecycle.transitionTo(ReleaseRuntimeState.starting);
      expect(
        () => lifecycle.transitionTo(ReleaseRuntimeState.starting),
        throwsStateError,
      );
    });

    test('fail() records the code and leaving error clears it', () {
      final lifecycle = ReleaseRuntimeLifecycle();
      lifecycle.transitionTo(ReleaseRuntimeState.starting);

      lifecycle.fail(ReleaseMcpErrorCode.transportStartFailed);

      expect(lifecycle.state, ReleaseRuntimeState.error);
      expect(lifecycle.errorCode, ReleaseMcpErrorCode.transportStartFailed);

      lifecycle.transitionTo(ReleaseRuntimeState.disabled);
      expect(lifecycle.errorCode, isNull);
    });

    test('error can be retried straight into starting', () {
      final lifecycle = ReleaseRuntimeLifecycle();
      lifecycle.transitionTo(ReleaseRuntimeState.starting);
      lifecycle.fail(ReleaseMcpErrorCode.transportStartFailed);

      expect(lifecycle.canTransitionTo(ReleaseRuntimeState.starting), isTrue);
      lifecycle.transitionTo(ReleaseRuntimeState.starting);
      expect(lifecycle.state, ReleaseRuntimeState.starting);
      expect(lifecycle.errorCode, isNull);
    });

    test('emits committed states on changes', () async {
      final lifecycle = ReleaseRuntimeLifecycle();
      final emissions = <ReleaseRuntimeState>[];
      final subscription = lifecycle.changes.listen(emissions.add);
      addTearDown(subscription.cancel);

      lifecycle.transitionTo(ReleaseRuntimeState.starting);
      lifecycle.transitionTo(ReleaseRuntimeState.running);
      lifecycle.transitionTo(ReleaseRuntimeState.stopping);
      lifecycle.transitionTo(ReleaseRuntimeState.disabled);

      await pumpEventQueue();

      expect(emissions, <ReleaseRuntimeState>[
        ReleaseRuntimeState.starting,
        ReleaseRuntimeState.running,
        ReleaseRuntimeState.stopping,
        ReleaseRuntimeState.disabled,
      ]);
      await lifecycle.close();
    });

    test('close() is idempotent and blocks further transitions', () async {
      final lifecycle = ReleaseRuntimeLifecycle();

      await lifecycle.close();
      await lifecycle.close();

      expect(lifecycle.isClosed, isTrue);
      expect(
        () => lifecycle.transitionTo(ReleaseRuntimeState.starting),
        throwsStateError,
      );
    });

    test('state helpers describe serving and transitional states', () {
      expect(ReleaseRuntimeState.starting.isTransitional, isTrue);
      expect(ReleaseRuntimeState.stopping.isTransitional, isTrue);
      expect(ReleaseRuntimeState.running.isServing, isTrue);
      expect(ReleaseRuntimeState.disabled.isServing, isFalse);
      expect(ReleaseRuntimeState.running.wireName, 'running');
    });
  });
}
