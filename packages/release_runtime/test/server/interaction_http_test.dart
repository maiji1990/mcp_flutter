// packages/release_runtime/test/server/interaction_http_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

import '../support/fake_interaction_driver.dart';
import '../support/fake_snapshot_source.dart';
import '../support/mcp_http_client.dart';

ReleaseUiNode _node(
  String ref, {
  String type = 'button',
  String? label,
  List<String> actions = const <String>['tap'],
  bool sensitive = false,
}) => ReleaseUiNode(
  ref: ref,
  id: ref.hashCode,
  type: type,
  bounds: const ReleaseUiRect(left: 0, top: 0, right: 120, bottom: 48),
  label: label,
  actions: actions,
  sensitive: sensitive,
  visibleInViewport: true,
  centerInViewport: true,
);

List<ReleaseUiNode> _nodes() => <ReleaseUiNode>[
  _node('s_0', label: 'Pay now'),
  _node('s_1', type: 'textField', actions: const <String>['setText']),
  _node(
    's_2',
    type: 'textField',
    actions: const <String>['setText'],
    sensitive: true,
  ),
];

void main() {
  late ReleaseMcpRuntime runtime;
  late McpTestClient client;
  late FakeDriver driver;

  setUp(() async {
    driver = FakeDriver();
    final store = ReleaseSnapshotStore();
    runtime = ReleaseMcpRuntime.http(
      config: const ReleaseMcpConfig(port: 0),
      tools: ReleaseToolbox(<ReleaseToolSurface>[
        ReleaseReadTools(
          source: FakeSnapshotSource(nodes: _nodes()),
          store: store,
        ),
        ReleaseInteractionTools(store: store, driver: driver),
      ]),
    );
    final status = await runtime.start();
    client = McpTestClient(status.endpoint!, runtime.accessToken.value);
    await client.initialize();
  });

  tearDown(() async {
    await runtime.dispose();
  });

  test('lists the read and write tools together', () async {
    final tools = await client.listTools();

    expect(tools.map((tool) => tool['name']), <String>[
      'ui_get_tree',
      'ui_get_current_page',
      'ui_find_element',
      'ui_click',
      'ui_set_text',
      'ui_scroll',
    ]);
  });

  test('a read-only session cannot click', () async {
    final tree = await client.callTool('ui_get_tree', <String, Object?>{});
    final snapshotId = releasePayloadOf(tree!)['snapshotId']! as String;
    final ref =
        ((releasePayloadOf(tree)['data']! as Map<String, dynamic>)['nodes']!
                    as List<Object?>)
                .cast<Map<String, dynamic>>()
                .first['ref']!
            as String;

    final click = await client.callTool('ui_click', <String, Object?>{
      'ref': ref,
      'snapshotId': snapshotId,
    });

    expect(click!['isError'], isTrue);
    final payload = releasePayloadOf(click);
    expect(payload['success'], isFalse);
    expect(
      (payload['error']! as Map<String, dynamic>)['code'],
      ReleaseMcpErrorCode.permissionDenied,
    );
    expect(driver.tapped, isEmpty);
  });

  test(
    'with consent a click is dispatched, then the snapshot is spent',
    () async {
      await runtime.grantPermissions(<ReleasePermissionId>[
        ReleasePermissionId.uiInteract,
      ]);

      final tree = await client.callTool('ui_get_tree', <String, Object?>{});
      final payload = releasePayloadOf(tree!);
      final snapshotId = payload['snapshotId']! as String;
      final nodes =
          (payload['data']! as Map<String, dynamic>)['nodes']! as List<Object?>;
      final ref = nodes.cast<Map<String, dynamic>>().first['ref']! as String;

      final click = await client.callTool('ui_click', <String, Object?>{
        'ref': ref,
        'snapshotId': snapshotId,
      });

      expect(click!['isError'], isFalse);
      final clicked = releasePayloadOf(click);
      expect(clicked['success'], isTrue);
      expect((clicked['data']! as Map<String, dynamic>)['dispatched'], isTrue);
      expect(driver.tapped, <String>[ref]);

      final again = await client.callTool('ui_click', <String, Object?>{
        'ref': ref,
        'snapshotId': snapshotId,
      });

      expect(again!['isError'], isTrue);
      expect(
        (releasePayloadOf(again)['error']! as Map<String, dynamic>)['code'],
        ReleaseMcpErrorCode.staleSnapshot,
      );
      expect(driver.tapped, hasLength(1));
    },
  );

  test('ui_set_text refuses a sensitive field over the wire', () async {
    await runtime.grantPermissions(<ReleasePermissionId>[
      ReleasePermissionId.uiInteract,
    ]);

    final tree = await client.callTool('ui_get_tree', <String, Object?>{});
    final payload = releasePayloadOf(tree!);
    final snapshotId = payload['snapshotId']! as String;
    final nodes =
        (payload['data']! as Map<String, dynamic>)['nodes']! as List<Object?>;
    final pin = nodes.cast<Map<String, dynamic>>().firstWhere(
      (node) => node['ref'] == 's_2',
    );

    final typed = await client.callTool('ui_set_text', <String, Object?>{
      'ref': pin['ref'],
      'text': '123456',
      'snapshotId': snapshotId,
    });

    expect(typed!['isError'], isTrue);
    expect(
      (releasePayloadOf(typed)['error']! as Map<String, dynamic>)['code'],
      ReleaseMcpErrorCode.nodeSensitive,
    );
    expect(typed.toString(), isNot(contains('123456')));
    expect(driver.typed, isEmpty);
  });

  test('ui_scroll validates its direction before acting', () async {
    await runtime.grantPermissions(<ReleasePermissionId>[
      ReleasePermissionId.uiInteract,
    ]);

    final tree = await client.callTool('ui_get_tree', <String, Object?>{});
    final payload = releasePayloadOf(tree!);

    // The SDK validates against the declared input schema first, so a value
    // outside the enum is refused before the runtime's own argument check. That
    // refusal is a JSON-RPC error, not a tool result, so inspect the envelope.
    final response = await client.send(
      <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 99,
        'method': 'tools/call',
        'params': <String, dynamic>{
          'name': 'ui_scroll',
          'arguments': <String, Object?>{
            'ref': 's_0',
            'direction': 'diagonal',
            'snapshotId': payload['snapshotId'],
          },
        },
      },
      extraHeaders: <String, String>{
        'mcp-name': 'ui_scroll',
        'mcp-method': 'tools/call',
      },
    );

    expect(response.statusCode, 200);
    expect(driver.scrolled, isEmpty);
    final result = response.payload?['result'];
    final rejected =
        response.payload?['error'] != null ||
        (result is Map<String, dynamic> && result['isError'] == true);
    expect(rejected, isTrue, reason: response.rawBody);
    expect(response.rawBody.toLowerCase(), contains('direction'));
  });
}
