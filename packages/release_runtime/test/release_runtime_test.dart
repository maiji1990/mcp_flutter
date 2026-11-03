// packages/release_runtime/test/release_runtime_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';

void main() {
  group('ReleaseMcpRuntime construction', () {
    test('binds nothing and stays disabled', () {
      final transport = FakeTransport();
      final runtime = ReleaseMcpRuntime(transport: transport);
      addTearDown(runtime.dispose);

      expect(runtime.state, ReleaseRuntimeState.disabled);
      expect(runtime.status.isServing, isFalse);
      expect(runtime.status.endpoint, isNull);
      expect(runtime.status.isReadOnly, isTrue);
      expect(runtime.status.grantedPermissions, ReleasePermissionSet.empty);
      expect(transport.startCalls, 0);
      expect(transport.stopCalls, 0);
    });

    test('enabledOnStartup is a hint, not an auto-start', () {
      final transport = FakeTransport();
      final runtime = ReleaseMcpRuntime(
        config: const ReleaseMcpConfig(enabledOnStartup: true),
        transport: transport,
      );
      addTearDown(runtime.dispose);

      expect(runtime.state, ReleaseRuntimeState.disabled);
      expect(transport.startCalls, 0);
      expect(runtime.status.config.enabledOnStartup, isTrue);
    });
  });

  group('ReleaseMcpRuntime start/stop', () {
    test('start() serves read-only and is idempotent', () async {
      final transport = FakeTransport();
      final runtime = ReleaseMcpRuntime(transport: transport);
      addTearDown(runtime.dispose);

      final first = await runtime.start();
      expect(first.state, ReleaseRuntimeState.running);
      expect(first.isReadOnly, isTrue);
      expect(first.grantedPermissions.toWireList(), <String>['ui:read']);
      expect(first.endpoint, isNull);
      expect(first.isListening, isFalse);
      expect(transport.startCalls, 1);
      expect(transport.lastRequest?.port, ReleaseMcpConfig.defaultPort);

      final second = await runtime.start();
      expect(second.state, ReleaseRuntimeState.running);
      expect(transport.startCalls, 1, reason: 'start is idempotent');
    });

    test('stop() releases the transport and clears the session', () async {
      final transport = FakeTransport();
      final runtime = ReleaseMcpRuntime(transport: transport);
      addTearDown(runtime.dispose);

      await runtime.start(
        authorization: ReleaseStartAuthorization(
          grantedPermissions: <ReleasePermissionId>[
            ReleasePermissionId.uiInteract,
          ],
        ),
      );
      expect(runtime.status.isReadOnly, isFalse);

      final stopped = await runtime.stop();
      expect(stopped.state, ReleaseRuntimeState.disabled);
      expect(stopped.grantedPermissions, ReleasePermissionSet.empty);
      expect(stopped.endpoint, isNull);
      expect(stopped.startedAt, isNull);
      expect(transport.stopCalls, 1);

      await runtime.stop();
      expect(transport.stopCalls, 1, reason: 'stop is idempotent');
    });

    test('a transport endpoint is reported on the status', () async {
      final transport = FakeTransport(
        endpoint: Uri.parse('http://127.0.0.1:8765/mcp'),
      );
      final runtime = ReleaseMcpRuntime(transport: transport);
      addTearDown(runtime.dispose);

      final status = await runtime.start();

      expect(status.endpoint.toString(), 'http://127.0.0.1:8765/mcp');
      expect(status.isListening, isTrue);
      expect(status.startedAt, isNotNull);
    });

    test('the default transport is inert and binds no endpoint', () async {
      final runtime = ReleaseMcpRuntime();
      addTearDown(runtime.dispose);

      final status = await runtime.start();

      expect(status.state, ReleaseRuntimeState.running);
      expect(status.endpoint, isNull);
    });

    test('start and stop are serialized under concurrent calls', () async {
      final transport = FakeTransport();
      final runtime = ReleaseMcpRuntime(transport: transport);
      addTearDown(runtime.dispose);

      final statuses = await Future.wait(
        List<Future<ReleaseRuntimeStatus>>.generate(5, (_) => runtime.start()),
      );

      expect(statuses, hasLength(5));
      expect(
        statuses.every((status) => status.state == ReleaseRuntimeState.running),
        isTrue,
      );
      expect(transport.startCalls, 1);

      await Future.wait(<Future<ReleaseRuntimeStatus>>[
        runtime.stop(),
        runtime.start(),
      ]);

      expect(runtime.state, ReleaseRuntimeState.running);
      expect(transport.startCalls, 2);
      expect(transport.stopCalls, 1);
    });
  });

  group('ReleaseMcpRuntime configuration and consent', () {
    test(
      'invalid config fails the start without touching the transport',
      () async {
        final transport = FakeTransport();
        final runtime = ReleaseMcpRuntime(
          config: const ReleaseMcpConfig(host: '0.0.0.0', port: 0),
          transport: transport,
        );
        addTearDown(runtime.dispose);

        await expectLater(
          runtime.start(),
          throwsA(
            isA<ReleaseMcpException>()
                .having(
                  (e) => e.code,
                  'code',
                  ReleaseMcpErrorCode.invalidConfig,
                )
                .having((e) => e.problems.single.field, 'field', 'host'),
          ),
        );

        expect(runtime.state, ReleaseRuntimeState.disabled);
        expect(transport.startCalls, 0);
      },
    );

    test('a non-read-only default requires explicit authorization', () async {
      final transport = FakeTransport();
      final runtime = ReleaseMcpRuntime(
        config: const ReleaseMcpConfig(readOnlyByDefault: false),
        transport: transport,
      );
      addTearDown(runtime.dispose);

      await expectLater(
        runtime.start(),
        throwsA(
          isA<ReleaseMcpException>().having(
            (error) => error.code,
            'code',
            ReleaseMcpErrorCode.authorizationMissing,
          ),
        ),
      );

      expect(runtime.state, ReleaseRuntimeState.disabled);
      expect(transport.startCalls, 0);
    });

    test('explicit grants survive start and are reported', () async {
      final runtime = ReleaseMcpRuntime(
        config: const ReleaseMcpConfig(readOnlyByDefault: false),
        transport: FakeTransport(),
      );
      addTearDown(runtime.dispose);

      final status = await runtime.start(
        authorization: ReleaseStartAuthorization(
          grantedPermissions: <ReleasePermissionId>[
            ReleasePermissionId.uiInteract,
            ReleasePermissionId.app('pay.invoice'),
          ],
          reason: 'user consented',
        ),
      );

      expect(status.state, ReleaseRuntimeState.running);
      expect(status.isReadOnly, isFalse);
      expect(status.grantedPermissions.toWireList(), <String>[
        'app:pay.invoice',
        'ui:interact',
        'ui:read',
      ]);
    });

    test('grant and revoke only work while serving', () async {
      final runtime = ReleaseMcpRuntime(transport: FakeTransport());
      addTearDown(runtime.dispose);

      await expectLater(
        runtime.grantPermissions(<ReleasePermissionId>[
          ReleasePermissionId.uiInteract,
        ]),
        throwsA(
          isA<ReleaseMcpException>().having(
            (error) => error.code,
            'code',
            ReleaseMcpErrorCode.runtimeNotRunning,
          ),
        ),
      );

      await runtime.start();
      final granted = await runtime.grantPermissions(<ReleasePermissionId>[
        ReleasePermissionId.uiCapture,
      ]);
      expect(granted.grantedPermissions.toWireList(), <String>[
        'ui:capture',
        'ui:read',
      ]);

      final revoked = await runtime.revokePermissions(<ReleasePermissionId>[
        ReleasePermissionId.uiCapture,
      ]);
      expect(revoked.grantedPermissions.toWireList(), <String>['ui:read']);
    });

    test('ui:read cannot be revoked away from a serving session', () async {
      final runtime = ReleaseMcpRuntime(transport: FakeTransport());
      addTearDown(runtime.dispose);

      await runtime.start();
      final status = await runtime.revokePermissions(<ReleasePermissionId>[
        ReleasePermissionId.uiRead,
      ]);

      expect(status.grantedPermissions.toWireList(), <String>['ui:read']);
      expect(status.isReadOnly, isTrue);
    });
  });

  group('ReleaseMcpRuntime failures', () {
    test('a failing transport lands in error with a stable code', () async {
      final transport = FakeTransport(startError: StateError('bind failed'));
      final runtime = ReleaseMcpRuntime(transport: transport);
      addTearDown(runtime.dispose);

      await expectLater(
        runtime.start(),
        throwsA(
          isA<ReleaseMcpException>()
              .having(
                (error) => error.code,
                'code',
                ReleaseMcpErrorCode.transportStartFailed,
              )
              .having((error) => error.details['cause'], 'cause', 'StateError'),
        ),
      );

      expect(runtime.state, ReleaseRuntimeState.error);
      expect(
        runtime.status.errorCode,
        ReleaseMcpErrorCode.transportStartFailed,
      );
      expect(runtime.status.grantedPermissions, ReleasePermissionSet.empty);

      final stopped = await runtime.stop();
      expect(stopped.state, ReleaseRuntimeState.disabled);
      expect(stopped.errorCode, isNull);
    });

    test('a failed stop is reported but leaves state consistent', () async {
      final transport = FakeTransport(stopError: StateError('close failed'));
      final runtime = ReleaseMcpRuntime(transport: transport);
      addTearDown(runtime.dispose);

      await runtime.start();

      await expectLater(
        runtime.stop(),
        throwsA(
          isA<ReleaseMcpException>().having(
            (error) => error.code,
            'code',
            ReleaseMcpErrorCode.transportStopFailed,
          ),
        ),
      );

      expect(runtime.state, ReleaseRuntimeState.error);
      expect(runtime.status.errorCode, ReleaseMcpErrorCode.transportStopFailed);
    });
  });

  group('ReleaseMcpRuntime lifecycle stream', () {
    test('emits starting, running, stopping, disabled in order', () async {
      final runtime = ReleaseMcpRuntime(transport: FakeTransport());
      addTearDown(runtime.dispose);

      final states = <ReleaseRuntimeState>[];
      final subscription = runtime.stateChanges.listen(states.add);
      addTearDown(subscription.cancel);

      final statuses = <ReleaseRuntimeState>[];
      final statusSubscription = runtime.statusChanges.listen(
        (status) => statuses.add(status.state),
      );
      addTearDown(statusSubscription.cancel);

      await runtime.start();
      await runtime.stop();
      await Future<void>.delayed(Duration.zero);

      expect(states, <ReleaseRuntimeState>[
        ReleaseRuntimeState.starting,
        ReleaseRuntimeState.running,
        ReleaseRuntimeState.stopping,
        ReleaseRuntimeState.disabled,
      ]);
      expect(statuses, <ReleaseRuntimeState>[
        ReleaseRuntimeState.starting,
        ReleaseRuntimeState.running,
        ReleaseRuntimeState.stopping,
        ReleaseRuntimeState.disabled,
      ]);
    });
  });

  group('ReleaseMcpRuntime dispose', () {
    test('is idempotent, stops the transport, and blocks restart', () async {
      final transport = FakeTransport();
      final runtime = ReleaseMcpRuntime(transport: transport);

      await runtime.start();
      await runtime.dispose();
      await runtime.dispose();

      expect(runtime.isDisposed, isTrue);
      expect(runtime.state, ReleaseRuntimeState.disabled);
      expect(transport.stopCalls, 1);
      expect(runtime.status.isDisposed, isTrue);

      await expectLater(
        runtime.start(),
        throwsA(
          isA<ReleaseMcpException>().having(
            (error) => error.code,
            'code',
            ReleaseMcpErrorCode.runtimeDisposed,
          ),
        ),
      );
    });

    test('dispose from a running session releases grants', () async {
      final runtime = ReleaseMcpRuntime(transport: FakeTransport());
      await runtime.start(
        authorization: ReleaseStartAuthorization(
          grantedPermissions: <ReleasePermissionId>[
            ReleasePermissionId.uiInteract,
          ],
        ),
      );

      await runtime.dispose();

      expect(runtime.status.grantedPermissions, ReleasePermissionSet.empty);
      expect(runtime.status.isReadOnly, isTrue);
    });
  });

  group('ReleaseMcpException', () {
    test('carries stable, non-sensitive descriptors', () {
      final error = ReleaseMcpException(ReleaseMcpErrorCode.permissionDenied);
      final json = error.toJson();

      expect(json['code'], 'permission_denied');
      expect(json['category'], ReleaseMcpErrorCategory.permission);
      expect(json['retryable'], isFalse);
      expect(json['httpLikeStatus'], 403);
      expect(error.retryable, isFalse);
      expect(error.message, contains('permission'));
    });

    test('unknown codes fall back to the generic descriptor', () {
      final error = ReleaseMcpException('not_a_real_code');

      expect(error.descriptor.code, ReleaseMcpErrorCode.unknown);
      expect(error.toJson()['httpLikeStatus'], 500);
    });
  });
}
