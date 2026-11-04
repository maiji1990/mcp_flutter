// packages/release_runtime/test/privacy/privacy_filter_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

ReleaseUiNode _node(
  String ref, {
  String type = 'label',
  String? identifier,
  String? label,
  String? value,
  String? hint,
  bool sensitive = false,
  List<String> children = const <String>[],
}) => ReleaseUiNode(
  ref: ref,
  id: ref.hashCode,
  type: type,
  bounds: const ReleaseUiRect(left: 0, top: 0, right: 10, bottom: 10),
  identifier: identifier,
  label: label,
  value: value,
  hint: hint,
  children: children,
  sensitive: sensitive,
);

ReleaseUiSnapshot _snapshot({String? routeName, List<ReleaseUiNode>? nodes}) =>
    ReleaseUiSnapshot(
      snapshotId: 'ui-1',
      nodes: nodes ?? <ReleaseUiNode>[_node('s_0', label: 'Hello')],
      capturedAt: DateTime.utc(2026, 11, 4, 9),
      routeName: routeName,
    );

void main() {
  test('a sensitive node loses label, value, and hint', () {
    const filter = RedactingPrivacyFilter();
    final verdict = filter.screen(
      _snapshot(
        nodes: <ReleaseUiNode>[
          _node(
            's_0',
            label: 'Card number',
            value: '4111 1111 1111 1111',
            hint: 'tap to copy',
            sensitive: true,
          ),
        ],
      ),
    );

    expect(verdict.isDenied, isFalse);
    final node = verdict.snapshot!.nodes.single;
    expect(node.label, '••••');
    expect(node.value, '••••');
    expect(node.hint, '••••');
    expect(node.sensitive, isTrue);
    expect(verdict.snapshot!.toJson().toString(), isNot(contains('4111')));
  });

  test('a denied route is a refusal with no snapshot', () {
    const filter = RedactingPrivacyFilter(
      policy: ReleaseUiPrivacyPolicy(deniedRoutes: <String>{'/wallet'}),
    );

    final verdict = filter.screen(
      _snapshot(
        routeName: '/wallet',
        nodes: <ReleaseUiNode>[_node('s_0', label: '4111 1111 1111 1111')],
      ),
    );

    expect(verdict.isDenied, isTrue);
    expect(verdict.denialCode, ReleaseMcpErrorCode.routeDenied);
    expect(verdict.reason, 'sensitive_route');
    expect(verdict.snapshot, isNull);
  });

  test('an unknown route can be denied when the app declares routes', () {
    const filter = RedactingPrivacyFilter(
      policy: ReleaseUiPrivacyPolicy(
        deniedRoutes: <String>{'/wallet'},
        denyWhenRouteUnknown: true,
      ),
    );

    expect(filter.routeDecision(null), ReleasePrivacyDecision.deny);
    expect(filter.routeDecision('/home'), ReleasePrivacyDecision.allow);
  });

  test('maskedRoutes masks every node, not only sensitive ones', () {
    const filter = RedactingPrivacyFilter(
      policy: ReleaseUiPrivacyPolicy(maskedRoutes: <String>{'/profile'}),
    );
    final verdict = filter.screen(
      _snapshot(
        routeName: '/profile',
        nodes: <ReleaseUiNode>[_node('s_0', label: 'Ada', value: 'ada@x')],
      ),
    );

    final node = verdict.snapshot!.nodes.single;
    expect(node.label, '••••');
    expect(node.value, '••••');
    expect(node.sensitive, isTrue);
  });

  test('maskAllValues masks every text field', () {
    const filter = RedactingPrivacyFilter(maskAllValues: true);
    final verdict = filter.screen(
      _snapshot(
        nodes: <ReleaseUiNode>[_node('s_0', label: 'Ada', value: 'x')],
      ),
    );

    final node = verdict.snapshot!.nodes.single;
    expect(node.value, '••••');
    expect(node.label, '••••');
    expect(node.sensitive, isTrue);
  });

  test('a denied identifier removes the whole subtree', () {
    const filter = RedactingPrivacyFilter(
      policy: ReleaseUiPrivacyPolicy(deniedIdentifiers: <String>{'secret'}),
    );
    final verdict = filter.screen(
      _snapshot(
        nodes: <ReleaseUiNode>[
          _node('s_0', label: 'Header'),
          _node(
            's_1',
            identifier: 'secret',
            label: 'Secret',
            children: const <String>['s_2'],
          ),
          _node('s_2', label: 'child'),
        ],
      ),
    );

    final refs = verdict.snapshot!.nodes.map((node) => node.ref).toList();
    expect(refs, contains('s_0'));
    expect(refs, isNot(contains('s_1')));
    expect(refs, isNot(contains('s_2')));
  });

  test('apply() degrades a denied snapshot to an empty one', () {
    const filter = RedactingPrivacyFilter(
      policy: ReleaseUiPrivacyPolicy(deniedRoutes: <String>{'/wallet'}),
    );

    final applied = filter.apply(_snapshot(routeName: '/wallet'));

    expect(applied.nodes, isEmpty);
    expect(applied.truncated, isTrue);
  });
}
