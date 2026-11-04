// packages/release_runtime/test/server/tools_http_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'dart:convert';

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

import '../support/fake_snapshot_source.dart';
import '../support/mcp_http_client.dart';

ReleaseUiNode _button(String ref, String label, {String? identifier}) =>
    ReleaseUiNode(
      ref: ref,
      id: ref.hashCode,
      type: 'button',
      bounds: const ReleaseUiRect(left: 0, top: 0, right: 120, bottom: 48),
      identifier: identifier,
      label: label,
      actions: const <String>['tap'],
      visibleInViewport: true,
      centerInViewport: true,
    );

FakeSnapshotSource _source() => FakeSnapshotSource(
  routeName: '/checkout',
  nodes: <ReleaseUiNode>[
    _button('s_0', 'Pay now', identifier: 'pay'),
    ReleaseUiNode(
      ref: 's_1',
      id: 2,
      type: 'textField',
      identifier: 'otp',
      label: 'One-time code',
      value: '123456',
      bounds: const ReleaseUiRect(left: 0, top: 60, right: 200, bottom: 100),
      actions: const <String>['setText'],
      sensitive: true,
      visibleInViewport: true,
      centerInViewport: true,
    ),
  ],
);

/// A surface used to exercise the runtime's permission gate.
final class _GatedSurface implements ReleaseToolSurface {
  _GatedSurface({this.throws = false});

  final bool throws;

  @override
  List<ReleaseToolDefinition> get tools => <ReleaseToolDefinition>[
    const ReleaseToolDefinition(
      name: 'app_pay_invoice',
      description: 'Business action that needs ui:interact.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
      permission: ReleasePermissionId.uiInteract,
    ),
    ReleaseToolDefinition(
      name: 'app_explode',
      description: 'A handler that throws.',
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
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
    if (throws) {
      throw StateError('boom');
    }
    return const ReleaseToolCallResult(
      requestId: 'r',
      success: true,
      data: <String, Object?>{'ok': true},
    );
  }
}

void main() {
  group('read tools over MCP HTTP', () {
    late ReleaseMcpRuntime runtime;
    late McpTestClient client;

    setUp(() async {
      runtime = ReleaseMcpRuntime.http(
        config: const ReleaseMcpConfig(port: 0),
        tools: ReleaseReadTools(source: _source()),
      );
      final status = await runtime.start();
      client = McpTestClient(status.endpoint!, runtime.accessToken.value);
      await client.initialize();
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('lists the three read tools', () async {
      final tools = await client.listTools();

      expect(tools.map((tool) => tool['name']), <String>[
        'ui_get_tree',
        'ui_get_current_page',
        'ui_find_element',
      ]);
      for (final tool in tools) {
        expect(tool['inputSchema'], isA<Map<String, dynamic>>());
      }
    });

    test('ui_get_tree returns a redacted tree over the wire', () async {
      final result = await client.callTool('ui_get_tree', <String, Object?>{});

      expect(result, isNotNull);
      expect(result!['isError'], isFalse);
      final content = result['content']! as List<Object?>;
      final payload = jsonDecode(
        (content.single as Map<String, dynamic>)['text'] as String,
      ) as Map<String, dynamic>;

      expect(payload['success'], isTrue);
      expect(payload['snapshotId'], 'ui-1');
      final data = payload['data']! as Map<String, dynamic>;
      expect(data['nodeCount'], 2);
      expect(data['routeName'], '/checkout');

      final nodes = (data['nodes']! as List<Object?>)
          .cast<Map<String, dynamic>>();
      final otp = nodes.firstWhere((node) => node['identifier'] == 'otp');
      expect(otp['value'], '••••');
      expect(
        (content.single as Map<String, dynamic>)['text'],
        isNot(contains('123456')),
      );
    });

    test('ui_find_element answers a single match', () async {
      final result = await client.callTool('ui_find_element', <String, Object?>{
        'identifier': 'pay',
      });

      final payload = _payloadOf(result!);
      expect(payload['success'], isTrue);
      final node =
          (payload['data']! as Map<String, dynamic>)['node']!
              as Map<String, dynamic>;
      expect(node['ref'], 's_0');
      expect(node['label'], 'Pay now');
    });

    test(
      'a tool-level refusal arrives as isError with a stable code',
      () async {
        final result = await client.callTool(
          'ui_find_element',
          <String, Object?>{'label': 'does not exist'},
        );

        expect(result!['isError'], isTrue);
        final payload = _payloadOf(result);
        expect(payload['success'], isFalse);
        expect(
          (payload['error']! as Map<String, dynamic>)['code'],
          ReleaseMcpErrorCode.elementNotFound,
        );
      },
    );
  });

  group('permission gate', () {
    test('a read-only session cannot call a ui:interact tool', () async {
      final runtime = ReleaseMcpRuntime.http(
        config: const ReleaseMcpConfig(port: 0),
        tools: _GatedSurface(),
      );
      addTearDown(runtime.dispose);
      final status = await runtime.start();
      final client = McpTestClient(status.endpoint!, runtime.accessToken.value);
      await client.initialize();

      final result = await client.callTool(
        'app_pay_invoice',
        <String, Object?>{},
      );

      expect(result!['isError'], isTrue);
      final payload = _payloadOf(result);
      expect(payload['success'], isFalse);
      final error = payload['error']! as Map<String, dynamic>;
      expect(error['code'], ReleaseMcpErrorCode.permissionDenied);
      expect(
        (error['details']! as Map<String, dynamic>)['permission'],
        'ui:interact',
      );
    });

    test('the same tool works once consent is granted', () async {
      final runtime = ReleaseMcpRuntime.http(
        config: const ReleaseMcpConfig(port: 0),
        tools: _GatedSurface(),
      );
      addTearDown(runtime.dispose);
      final status = await runtime.start(
        authorization: ReleaseStartAuthorization(
          grantedPermissions: <ReleasePermissionId>[
            ReleasePermissionId.uiInteract,
          ],
        ),
      );
      final client = McpTestClient(status.endpoint!, runtime.accessToken.value);
      await client.initialize();

      final result = await client.callTool(
        'app_pay_invoice',
        <String, Object?>{},
      );

      expect(result!['isError'], isFalse);
      expect(_payloadOf(result)['success'], isTrue);
    });

    test(
      'a throwing handler becomes unknown_error, not a stack trace',
      () async {
        final runtime = ReleaseMcpRuntime.http(
          config: const ReleaseMcpConfig(port: 0),
          tools: _GatedSurface(throws: true),
        );
        addTearDown(runtime.dispose);
        final status = await runtime.start();
        final client = McpTestClient(
          status.endpoint!,
          runtime.accessToken.value,
        );
        await client.initialize();

        final result = await client.callTool(
          'app_explode',
          <String, Object?>{},
        );

        expect(result!['isError'], isTrue);
        final payload = _payloadOf(result);
        final error = payload['error']! as Map<String, dynamic>;
        expect(error['code'], ReleaseMcpErrorCode.unknown);
        expect(
          (error['details']! as Map<String, dynamic>)['cause'],
          'StateError',
        );
        expect(jsonEncode(payload), isNot(contains('boom')));
      },
    );
  });
}

Map<String, dynamic> _payloadOf(Map<String, dynamic> result) {
  final content = result['content']! as List<Object?>;
  return jsonDecode((content.single as Map<String, dynamic>)['text'] as String)
      as Map<String, dynamic>;
}
