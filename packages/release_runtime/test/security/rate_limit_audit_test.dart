// packages/release_runtime/test/security/rate_limit_audit_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

import '../support/fake_transport.dart';

final class _Surface implements ReleaseToolSurface {
  int calls = 0;

  @override
  List<ReleaseToolDefinition> get tools => const <ReleaseToolDefinition>[
    ReleaseToolDefinition(
      name: 'echo',
      description: 'echo',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
      permission: ReleasePermissionId.uiRead,
    ),
    ReleaseToolDefinition(
      name: 'write',
      description: 'write',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
      permission: ReleasePermissionId.uiInteract,
    ),
  ];

  @override
  Future<ReleaseToolCallResult> call(
    String name,
    Map<String, Object?> arguments, {
    ReleaseCallAuthorization? authorization,
  }) async {
    calls += 1;
    return ReleaseToolCallResult(
      requestId: 'r',
      success: true,
      data: <String, Object?>{'echo': arguments['value']},
    );
  }
}

void main() {
  test('the rate limiter refuses calls over the window budget', () async {
    final surface = _Surface();
    final transport = FakeTransport();
    final runtime = ReleaseMcpRuntime(
      transport: transport,
      tools: surface,
      rateLimit: const ReleaseRateLimit(maxRequests: 3),
    );
    await runtime.start();
    final guarded = transport.lastRequest!.toolSurface!;

    for (var i = 0; i < 3; i += 1) {
      final result = await guarded.call('echo', const <String, Object?>{});
      expect(result.success, isTrue, reason: result.error?.message);
    }
    final refused = await guarded.call('echo', const <String, Object?>{});

    expect(refused.success, isFalse);
    expect(refused.error!.code, ReleaseMcpErrorCode.rateLimited);
    expect(refused.error!.details['limit'], 3);
    expect(surface.calls, 3, reason: 'the fourth call never reached the tool');

    await runtime.dispose();
  });

  test('audit records the decision and argument keys, never values', () async {
    final events = <ReleaseAuditEvent>[];
    final transport = FakeTransport();
    final runtime = ReleaseMcpRuntime(
      transport: transport,
      tools: _Surface(),
      auditSink: events.add,
    );
    await runtime.start();
    final guarded = transport.lastRequest!.toolSurface!;

    await guarded.call('echo', <String, Object?>{'value': 'super-secret'});
    await guarded.call('write', const <String, Object?>{});

    expect(events, hasLength(2));
    expect(events.first.tool, 'echo');
    expect(events.first.allowed, isTrue);
    expect(events.first.argumentKeys, <String>['value']);
    expect(events.last.allowed, isFalse);
    expect(events.last.reason, ReleaseMcpErrorCode.permissionDenied);
    final encoded = events.map((event) => event.toJson().toString()).join();
    expect(encoded, isNot(contains('super-secret')));

    await runtime.dispose();
  });

  test('a throwing audit sink does not break the call', () async {
    final transport = FakeTransport();
    final runtime = ReleaseMcpRuntime(
      transport: transport,
      tools: _Surface(),
      auditSink: (event) => throw StateError('sink down'),
    );
    await runtime.start();
    final guarded = transport.lastRequest!.toolSurface!;

    final result = await guarded.call('echo', const <String, Object?>{});

    expect(result.success, isTrue, reason: result.error?.message);
    await runtime.dispose();
  });
}
