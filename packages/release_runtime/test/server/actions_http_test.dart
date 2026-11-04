// packages/release_runtime/test/server/actions_http_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

import '../support/fake_capture_source.dart';
import '../support/fake_interaction_driver.dart';
import '../support/fake_snapshot_source.dart';
import '../support/mcp_http_client.dart';

void main() {
  late ReleaseMcpRuntime runtime;
  late McpTestClient client;
  var paid = 0;

  ReleaseToolSurface buildTools() {
    final store = ReleaseSnapshotStore();
    return ReleaseToolbox(<ReleaseToolSurface>[
      ReleaseReadTools(
        source: FakeSnapshotSource(nodes: const <ReleaseUiNode>[]),
        store: store,
      ),
      ReleaseInteractionTools(store: store, driver: FakeDriver()),
      ReleaseAppActionTools(<ReleaseAppAction>[
        ReleaseAppAction(
          name: 'pay.invoice',
          description: 'Pay an invoice',
          inputSchema: const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'invoiceId': <String, Object?>{'type': 'string', 'maxLength': 64},
            },
            'required': <String>['invoiceId'],
            'additionalProperties': false,
          },
          handler: (arguments) async {
            paid += 1;
            return <String, Object?>{'invoiceId': arguments['invoiceId']};
          },
        ),
      ]),
      ReleaseCaptureTools(
        source: FakeCaptureSource(routeName: '/home'),
        policy: const ReleaseCapturePolicy(allowedRoutes: <String>{'/home'}),
        maxBytes: 4096,
      ),
    ]);
  }

  setUp(() async {
    paid = 0;
    runtime = ReleaseMcpRuntime.http(
      config: const ReleaseMcpConfig(port: 0),
      tools: buildTools(),
    );
    final status = await runtime.start();
    client = McpTestClient(status.endpoint!, runtime.accessToken.value);
    await client.initialize();
  });

  tearDown(() async {
    await runtime.dispose();
  });

  test('lists every release tool', () async {
    final tools = await client.listTools();

    expect(tools.map((tool) => tool['name']), <String>[
      'ui_get_tree',
      'ui_get_current_page',
      'ui_find_element',
      'ui_click',
      'ui_set_text',
      'ui_scroll',
      'app_invoke_action',
      'ui_capture',
    ]);
  });

  test('a business action needs its own app: consent', () async {
    final denied = await client.callTool('app_invoke_action', <String, Object?>{
      'name': 'pay.invoice',
      'arguments': <String, Object?>{'invoiceId': 'INV-1'},
    });

    expect(denied!['isError'], isTrue);
    final payload = releasePayloadOf(denied);
    expect(
      (payload['error']! as Map<String, dynamic>)['code'],
      ReleaseMcpErrorCode.permissionDenied,
    );
    expect(
      ((payload['error']! as Map<String, dynamic>)['details']!
          as Map<String, dynamic>)['permission'],
      'app:pay.invoice',
    );
    expect(paid, 0);
  });

  test('with consent the action runs end to end', () async {
    await runtime.grantPermissions(<ReleasePermissionId>[
      ReleasePermissionId.app('pay.invoice'),
    ]);

    final result = await client.callTool('app_invoke_action', <String, Object?>{
      'name': 'pay.invoice',
      'arguments': <String, Object?>{'invoiceId': 'INV-2'},
    });

    expect(result!['isError'], isFalse);
    final payload = releasePayloadOf(result);
    expect(payload['success'], isTrue);
    final data = payload['data']! as Map<String, dynamic>;
    expect((data['result']! as Map<String, dynamic>)['invoiceId'], 'INV-2');
    expect(paid, 1);
  });

  test('an unregistered action never reaches the handler', () async {
    // The catalog advertises the registered names as an enum, so the SDK
    // refuses an unknown one at the protocol layer. The runtime's own
    // action_not_found path is covered by the core tests.
    final response = await client.send(
      <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 77,
        'method': 'tools/call',
        'params': <String, dynamic>{
          'name': 'app_invoke_action',
          'arguments': <String, Object?>{'name': 'refund'},
        },
      },
      extraHeaders: <String, String>{
        'mcp-name': 'app_invoke_action',
        'mcp-method': 'tools/call',
      },
    );

    expect(response.statusCode, 200);
    expect(paid, 0);
    final result = response.payload?['result'];
    final rejected =
        response.payload?['error'] != null ||
        (result is Map<String, dynamic> && result['isError'] == true);
    expect(rejected, isTrue, reason: response.rawBody);
  });

  test('capture needs ui:capture', () async {
    final denied = await client.callTool('ui_capture', <String, Object?>{});

    expect(denied!['isError'], isTrue);
    expect(
      (releasePayloadOf(denied)['error']! as Map<String, dynamic>)['code'],
      ReleaseMcpErrorCode.permissionDenied,
    );
  });

  test('with consent capture returns a png payload', () async {
    await runtime.grantPermissions(<ReleasePermissionId>[
      ReleasePermissionId.uiCapture,
    ]);

    final result = await client.callTool('ui_capture', <String, Object?>{
      'scale': 0.5,
    });

    expect(result!['isError'], isFalse);
    final data = releasePayloadOf(result)['data']! as Map<String, dynamic>;
    expect(data['mimeType'], 'image/png');
    expect(data['scale'], 0.5);
    expect(data['bytesBase64'], isA<String>());
  });
}
