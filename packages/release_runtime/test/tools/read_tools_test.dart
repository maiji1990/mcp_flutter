// packages/release_runtime/test/tools/read_tools_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

import '../support/fake_snapshot_source.dart';

ReleaseUiNode _node(
  String ref, {
  String type = 'button',
  String? identifier,
  String? label,
  String? value,
  List<String> children = const <String>[],
  List<String> actions = const <String>['tap'],
  bool sensitive = false,
  int id = 0,
}) => ReleaseUiNode(
  ref: ref,
  id: id,
  type: type,
  bounds: const ReleaseUiRect(left: 0, top: 0, right: 100, bottom: 40),
  identifier: identifier,
  label: label,
  value: value,
  actions: actions,
  children: children,
  sensitive: sensitive,
  visibleInViewport: true,
  centerInViewport: true,
);

FakeSnapshotSource _source() => FakeSnapshotSource(
  routeName: '/home',
  nodes: <ReleaseUiNode>[
    _node('s_0', type: 'root', label: 'Home', children: <String>['s_1', 's_2']),
    _node('s_1', identifier: 'save', label: 'Save'),
    _node(
      's_2',
      type: 'textField',
      identifier: 'pin',
      label: 'PIN',
      value: 'hunter2',
      actions: <String>['setText'],
      sensitive: true,
    ),
    _node('s_3', identifier: 'settings', label: 'Settings'),
  ],
);

void main() {
  group('ui_get_tree', () {
    test('returns the tree with refs and a snapshot id', () async {
      final releaseTools = ReleaseReadTools(source: _source());

      final result = await releaseTools.call(
        'ui_get_tree',
        <String, Object?>{},
      );

      expect(result.success, isTrue);
      expect(result.snapshotId, 'ui-1');
      expect(result.error, isNull);
      final data = result.data!;
      expect(data['nodeCount'], 4);
      expect(data['truncated'], isFalse);
      expect(data['routeName'], '/home');
      final nodes = data['nodes']! as List<Object?>;
      expect(nodes, hasLength(4));
      expect((nodes.first! as Map<String, Object?>)['ref'], 's_0');
      expect(result.toJson()['success'], isTrue);
    });

    test('masks a sensitive value but keeps its label', () async {
      final releaseTools = ReleaseReadTools(source: _source());

      final result = await releaseTools.call(
        'ui_get_tree',
        <String, Object?>{},
      );

      final nodes = result.data!['nodes']! as List<Object?>;
      final pin = nodes.cast<Map<String, Object?>>().firstWhere(
        (node) => node['identifier'] == 'pin',
      );
      expect(pin['value'], '••••');
      expect(pin['label'], 'PIN');
      expect(pin['sensitive'], isTrue);
      expect(result.data.toString(), isNot(contains('hunter2')));
    });

    test('maxNodes caps the answer and flags truncation', () async {
      final releaseTools = ReleaseReadTools(source: _source());

      final result = await releaseTools.call('ui_get_tree', <String, Object?>{
        'maxNodes': 2,
      });

      expect(result.success, isTrue);
      expect(result.data!['nodeCount'], 2);
      expect(result.data!['truncated'], isTrue);
      expect(result.data!['totalNodeCount'], 4);
    });

    test('maxDepth walks only the requested levels', () async {
      final releaseTools = ReleaseReadTools(source: _source());

      final depthZero = await releaseTools.call(
        'ui_get_tree',
        <String, Object?>{'maxDepth': 0},
      );
      final refsZero = (depthZero.data!['nodes']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map((node) => node['ref'])
          .toList();
      expect(refsZero, <String>['s_0', 's_3']);

      final depthOne = await releaseTools.call('ui_get_tree', <String, Object?>{
        'maxDepth': 1,
      });
      final refsOne = (depthOne.data!['nodes']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map((node) => node['ref'])
          .toList();
      expect(refsOne, <String>['s_0', 's_1', 's_2', 's_3']);
    });

    test('passes the identifier filter down to the source', () async {
      final source = _source();
      final releaseTools = ReleaseReadTools(source: source);

      final result = await releaseTools.call('ui_get_tree', <String, Object?>{
        'filter': 'sa',
      });

      expect(result.success, isTrue);
      final nodes = result.data!['nodes']! as List<Object?>;
      expect(nodes, hasLength(1));
      expect(result.data!['filter'], 'sa');
    });

    test('rejects a nonsensical maxNodes without echoing the input', () async {
      final releaseTools = ReleaseReadTools(source: _source());

      final tooBig = await releaseTools.call('ui_get_tree', <String, Object?>{
        'maxNodes': 100000,
      });
      final wrongType = await releaseTools.call(
        'ui_get_tree',
        <String, Object?>{'maxNodes': 'many'},
      );

      for (final result in <ReleaseToolCallResult>[tooBig, wrongType]) {
        expect(result.success, isFalse);
        expect(result.error!.code, ReleaseMcpErrorCode.invalidArgument);
        expect(result.error!.message, isNotEmpty);
        expect(result.error!.message, isNot(contains('many')));
        expect(result.error!.message, isNot(contains('100000')));
      }
    });
  });

  group('ui_get_current_page', () {
    test('reports route, surface, and node count', () async {
      final releaseTools = ReleaseReadTools(source: _source());

      final result = await releaseTools.call(
        'ui_get_current_page',
        <String, Object?>{},
      );

      expect(result.success, isTrue);
      expect(result.snapshotId, 'ui-1');
      expect(result.data!['routeName'], '/home');
      expect(result.data!['interactionSurface'], 'rich');
      expect(result.data!['nodeCount'], 4);
    });
  });

  group('ui_find_element', () {
    test('finds one node by label, case-insensitively', () async {
      final releaseTools = ReleaseReadTools(source: _source());

      final result = await releaseTools.call(
        'ui_find_element',
        <String, Object?>{'label': 'save'},
      );

      expect(result.success, isTrue);
      expect(result.snapshotId, 'ui-1');
      final node = result.data!['node']! as Map<String, Object?>;
      expect(node['ref'], 's_1');
      expect(node['identifier'], 'save');
    });

    test('finds by identifier and by role', () async {
      final releaseTools = ReleaseReadTools(source: _source());

      final byIdentifier = await releaseTools.call(
        'ui_find_element',
        <String, Object?>{'identifier': 'settings'},
      );
      expect(byIdentifier.success, isTrue);
      expect(
        (byIdentifier.data!['node']! as Map<String, Object?>)['ref'],
        's_3',
      );

      final byRole = await releaseTools.call(
        'ui_find_element',
        <String, Object?>{'role': 'textField'},
      );
      expect(byRole.success, isTrue);
      expect((byRole.data!['node']! as Map<String, Object?>)['ref'], 's_2');
      // Even a found password field comes back redacted.
      expect((byRole.data!['node']! as Map<String, Object?>)['value'], '••••');
    });

    test('refuses an empty query and a missing match', () async {
      final releaseTools = ReleaseReadTools(source: _source());

      final empty = await releaseTools.call(
        'ui_find_element',
        <String, Object?>{},
      );
      expect(empty.success, isFalse);
      expect(empty.error!.code, ReleaseMcpErrorCode.invalidArgument);

      final missing = await releaseTools.call(
        'ui_find_element',
        <String, Object?>{'label': 'Not here'},
      );
      expect(missing.success, isFalse);
      expect(missing.error!.code, ReleaseMcpErrorCode.elementNotFound);
      expect(missing.snapshotId, 'ui-1');
      expect(missing.error!.message, isNot(contains('Not here')));
    });

    test('refuses an ambiguous query and lists the candidates', () async {
      final source = FakeSnapshotSource(
        nodes: <ReleaseUiNode>[
          _node('s_0', label: 'Delete'),
          _node('s_1', label: 'Delete'),
        ],
      );
      final releaseTools = ReleaseReadTools(source: source);

      final result = await releaseTools.call(
        'ui_find_element',
        <String, Object?>{'label': 'Delete'},
      );

      expect(result.success, isFalse);
      expect(result.error!.code, ReleaseMcpErrorCode.ambiguousMatch);
      expect(result.error!.details['matchCount'], 2);
      expect(result.error!.details['refs'], <String>['s_0', 's_1']);
    });
  });

  group('privacy', () {
    test('maskAllValues hides every field value', () async {
      final source = FakeSnapshotSource(
        nodes: <ReleaseUiNode>[_node('s_0', value: 'plain', type: 'textField')],
      );
      final releaseTools = ReleaseReadTools(
        source: source,
        privacy: const RedactingPrivacyFilter(maskAllValues: true),
      );

      final result = await releaseTools.call(
        'ui_get_tree',
        <String, Object?>{},
      );

      final node =
          (result.data!['nodes']! as List<Object?>).single
              as Map<String, Object?>;
      expect(node['value'], '••••');
    });

    test('truncates long text with an ellipsis', () async {
      final longLabel = 'x' * 400;
      final source = FakeSnapshotSource(
        nodes: <ReleaseUiNode>[_node('s_0', label: longLabel)],
      );
      final releaseTools = ReleaseReadTools(
        source: source,
        privacy: const RedactingPrivacyFilter(maxTextLength: 20),
      );

      final result = await releaseTools.call(
        'ui_get_tree',
        <String, Object?>{},
      );

      final label =
          ((result.data!['nodes']! as List<Object?>).single
                  as Map<String, Object?>)['label']!
              as String;
      expect(label.length, 21);
      expect(label.endsWith('…'), isTrue);
    });
  });

  group('catalog', () {
    test('the three read tools are declared with ui:read', () {
      final releaseTools = ReleaseReadTools(source: _source());

      expect(releaseTools.tools.map((tool) => tool.name), <String>[
        'ui_get_tree',
        'ui_get_current_page',
        'ui_find_element',
      ]);
      for (final tool in releaseTools.tools) {
        expect(tool.permission, ReleasePermissionId.uiRead);
        expect(tool.inputSchema['type'], 'object');
        expect(tool.description, isNotEmpty);
      }
    });
  });
}
