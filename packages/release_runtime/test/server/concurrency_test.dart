// packages/release_runtime/test/server/concurrency_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'dart:async';

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

import '../support/fake_transport.dart';

/// A surface whose handler blocks until the test releases [gate].
final class _SlowSurface implements ReleaseToolSurface {
  _SlowSurface();

  final Completer<void> gate = Completer<void>();
  int active = 0;
  int maxActive = 0;
  int calls = 0;

  @override
  List<ReleaseToolDefinition> get tools => const <ReleaseToolDefinition>[
    ReleaseToolDefinition(
      name: 'slow',
      description: 'blocks until the gate opens',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.uiRead,
    ),
  ];

  @override
  Future<ReleaseToolCallResult> call(
    String name,
    Map<String, Object?> arguments, {
    ReleaseCallAuthorization? authorization,
  }) async {
    calls += 1;
    active += 1;
    if (active > maxActive) {
      maxActive = active;
    }
    await gate.future;
    active -= 1;
    return const ReleaseToolCallResult(requestId: 'r', success: true);
  }
}

void main() {
  test(
    'the guarded surface enforces maxConcurrentRequests and a bounded queue',
    () async {
      final surface = _SlowSurface();
      final transport = FakeTransport();
      final runtime = ReleaseMcpRuntime(
        config: const ReleaseMcpConfig(maxConcurrentRequests: 4),
        transport: transport,
        tools: surface,
      );
      await runtime.start();
      final guarded = transport.lastRequest!.toolSurface!;

      final calls = <Future<ReleaseToolCallResult>>[
        for (var i = 0; i < 25; i += 1)
          guarded.call('slow', <String, Object?>{}),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(surface.maxActive, lessThanOrEqualTo(4));
      expect(surface.calls, 4, reason: 'only the admitted calls start');

      surface.gate.complete();
      final results = await Future.wait(calls);

      expect(results.where((result) => result.success), hasLength(20));
      final busy = results.where(
        (result) => result.error?.code == ReleaseMcpErrorCode.serverBusy,
      );
      expect(busy, hasLength(5));
      expect(surface.calls, 20);

      await runtime.dispose();
    },
  );
}
