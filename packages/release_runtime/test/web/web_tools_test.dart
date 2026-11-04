// packages/release_runtime/test/web/web_tools_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

import '../support/fake_web_source.dart';

ReleaseWebNode _node(
  String ref, {
  String tag = 'button',
  String role = '',
  String type = '',
  String? label,
  String? text,
  String? value,
  bool sensitive = false,
}) => ReleaseWebNode(
  ref: ref,
  tag: tag,
  role: role,
  inputType: type,
  label: label,
  text: text,
  value: value,
  sensitive: sensitive,
);

FakeWebSource _source({List<ReleaseWebNode>? nodes}) => FakeWebSource(
  views: const <ReleaseWebViewInfo>[
    ReleaseWebViewInfo(
      viewId: 'orders',
      allowedOrigins: <String>{'https://app.example.com'},
      url: 'https://app.example.com/orders',
    ),
  ],
  nodes:
      nodes ??
      <ReleaseWebNode>[
        _node('w1_0', label: 'Search', text: 'Search'),
        _node(
          'w1_1',
          tag: 'input',
          role: 'textbox',
          type: 'password',
          label: 'Password',
          value: 'hunter2',
          sensitive: true,
        ),
        _node('w1_2', tag: 'a', label: 'Help', text: 'Help'),
      ],
);

void main() {
  group('web_list_views', () {
    test(
      'returns only the registered views, never a widget-tree scan',
      () async {
        final tools = ReleaseWebTools(source: _source());

        final result = await tools.call('web_list_views', <String, Object?>{});

        expect(result.success, isTrue);
        final views = result.data!['views']! as List<Object?>;
        expect(views, hasLength(1));
        final view = views.single! as Map<String, Object?>;
        expect(view['viewId'], 'orders');
        expect(view['allowedOrigins'], <String>['https://app.example.com']);
        expect(tools.tools.first.permission, ReleasePermissionId.webRead);
      },
    );
  });

  group('web_get_tree', () {
    test('returns bounded nodes and a snapshot id', () async {
      final source = _source();
      final tools = ReleaseWebTools(source: source);

      final result = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
        'maxNodes': 2,
      });

      expect(result.success, isTrue, reason: result.error?.message);
      expect(source.lastMaxNodes, 2);
      final data = result.data!;
      expect(data['url'], 'https://app.example.com/orders');
      expect(data['nodeCount'], 2);
      expect(data['navigationEpoch'], 1);
      expect(result.snapshotId, startsWith('web:orders:1:'));
    });

    test('masks a password value the adapter failed to redact', () async {
      final tools = ReleaseWebTools(source: _source());

      final result = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
      });

      expect(result.success, isTrue);
      final password = (result.data!['nodes']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere((node) => node['type'] == 'password');
      expect(password['value'], '••••');
      expect(password['label'], '••••');
      expect(result.toJson().toString(), isNot(contains('hunter2')));
    });

    test('a denied path is refused before any node is returned', () async {
      final tools = ReleaseWebTools(
        source: _source(),
        policy: const ReleaseWebPrivacyPolicy(
          deniedPathPrefixes: <String>{'/orders'},
        ),
      );

      final result = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
      });

      expect(result.success, isFalse);
      expect(result.error!.code, ReleaseMcpErrorCode.routeDenied);
      expect(result.data, isNull);
    });

    test('a non-web URL is refused', () async {
      final tools = ReleaseWebTools(
        source: FakeWebSource(url: 'file:///data/local/tmp/page.html'),
      );

      final result = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
      });

      expect(result.error!.code, ReleaseMcpErrorCode.routeDenied);
    });

    test('plain http is refused unless the app opts into staging', () async {
      final tools = ReleaseWebTools(
        source: FakeWebSource(url: 'http://app.example.com/orders'),
      );

      final result = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
      });

      expect(result.error!.code, ReleaseMcpErrorCode.routeDenied);
    });

    test('an invalid view id is refused without echoing it', () async {
      final tools = ReleaseWebTools(source: _source());

      final result = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'Not A View',
      });

      expect(result.error!.code, ReleaseMcpErrorCode.viewNotFound);
      expect(result.toJson().toString(), isNot(contains('Not A View')));
    });

    test('an adapter origin refusal maps to origin_denied', () async {
      final source = _source()..captureError = 'origin_denied';
      final tools = ReleaseWebTools(source: source);

      final result = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
      });

      expect(result.error!.code, ReleaseMcpErrorCode.originDenied);
    });
  });

  group('web_find_element', () {
    test('finds by text and returns refs from a fresh snapshot', () async {
      final tools = ReleaseWebTools(source: _source());

      final result = await tools.call('web_find_element', <String, Object?>{
        'viewId': 'orders',
        'text': 'search',
      });

      expect(result.success, isTrue, reason: result.error?.message);
      expect(result.data!['matchCount'], 1);
      final match =
          (result.data!['matches']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(match['ref'], 'w1_0');
    });

    test('a query that matches nothing is element_not_found', () async {
      final tools = ReleaseWebTools(source: _source());

      final result = await tools.call('web_find_element', <String, Object?>{
        'viewId': 'orders',
        'text': 'checkout',
      });

      expect(result.error!.code, ReleaseMcpErrorCode.elementNotFound);
    });
  });

  group('web actions', () {
    test('click dispatches and consumes the snapshot', () async {
      final source = _source();
      final tools = ReleaseWebTools(source: source);
      final tree = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
      });

      final click = await tools.call('web_click', <String, Object?>{
        'viewId': 'orders',
        'ref': 'w1_0',
        'snapshotId': tree.snapshotId,
      });
      final second = await tools.call('web_click', <String, Object?>{
        'viewId': 'orders',
        'ref': 'w1_0',
        'snapshotId': tree.snapshotId,
      });

      expect(click.success, isTrue, reason: click.error?.message);
      expect(source.actions, <String>['click']);
      expect(second.error!.code, ReleaseMcpErrorCode.staleSnapshot);
    });

    test('an action without a snapshotId is refused', () async {
      final tools = ReleaseWebTools(source: _source());

      final result = await tools.call('web_click', <String, Object?>{
        'viewId': 'orders',
        'ref': 'w1_0',
      });

      expect(result.error!.code, ReleaseMcpErrorCode.snapshotRequired);
    });

    test('an unknown ref is refused', () async {
      final source = _source();
      final tools = ReleaseWebTools(source: source);
      final tree = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
      });

      final result = await tools.call('web_click', <String, Object?>{
        'viewId': 'orders',
        'ref': 'w1_99',
        'snapshotId': tree.snapshotId,
      });

      expect(result.error!.code, ReleaseMcpErrorCode.unknownRef);
      expect(source.actions, isEmpty);
    });

    test('setText refuses a password field', () async {
      final source = _source();
      final tools = ReleaseWebTools(source: source);
      final tree = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
      });

      final result = await tools.call('web_set_text', <String, Object?>{
        'viewId': 'orders',
        'ref': 'w1_1',
        'snapshotId': tree.snapshotId,
        'text': 'guess',
      });

      expect(result.error!.code, ReleaseMcpErrorCode.nodeSensitive);
      expect(source.actions, isEmpty);
    });

    test('setText passes validated text to the adapter', () async {
      final source = _source();
      final tools = ReleaseWebTools(source: source);
      final tree = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
      });

      final result = await tools.call('web_set_text', <String, Object?>{
        'viewId': 'orders',
        'ref': 'w1_0',
        'snapshotId': tree.snapshotId,
        'text': 'invoice 42',
      });

      expect(result.success, isTrue, reason: result.error?.message);
      expect(source.lastText, 'invoice 42');
    });

    test('a withdrawn consent refuses the action before dispatch', () async {
      final source = _source();
      final tools = ReleaseWebTools(source: source);
      final tree = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
      });

      final result = await tools.call(
        'web_click',
        <String, Object?>{
          'viewId': 'orders',
          'ref': 'w1_0',
          'snapshotId': tree.snapshotId,
        },
        authorization: const ReleaseCallAuthorization(
          epoch: 1,
          grantProbe: _denyAll,
        ),
      );

      expect(result.error!.code, ReleaseMcpErrorCode.permissionDenied);
      expect(source.actions, isEmpty);
    });

    test('scroll validates direction and amount', () async {
      final source = _source();
      final tools = ReleaseWebTools(source: source);
      final tree = await tools.call('web_get_tree', <String, Object?>{
        'viewId': 'orders',
      });

      final badDirection = await tools.call('web_scroll', <String, Object?>{
        'viewId': 'orders',
        'ref': 'w1_0',
        'snapshotId': tree.snapshotId,
        'direction': 'sideways',
      });
      final badAmount = await tools.call('web_scroll', <String, Object?>{
        'viewId': 'orders',
        'ref': 'w1_0',
        'snapshotId': tree.snapshotId,
        'direction': 'down',
        'amount': 0,
      });

      expect(badDirection.error!.code, ReleaseMcpErrorCode.invalidArgument);
      expect(badAmount.error!.code, ReleaseMcpErrorCode.invalidArgument);
    });

    test('the interaction tools declare web:interact', () {
      final tools = ReleaseWebTools(source: _source());

      for (final name in <String>['web_click', 'web_set_text', 'web_scroll']) {
        final definition = tools.tools.firstWhere((tool) => tool.name == name);
        expect(definition.permission, ReleasePermissionId.webInteract);
      }
    });
  });

  group('web_get_state', () {
    test('reports the sanitized URL and epoch', () async {
      final tools = ReleaseWebTools(source: _source());

      final result = await tools.call('web_get_state', <String, Object?>{
        'viewId': 'orders',
      });

      expect(result.success, isTrue);
      expect(result.data!['url'], 'https://app.example.com/orders');
      expect(result.data!['navigationEpoch'], 1);
    });
  });
}

bool _denyAll(ReleasePermissionId permission) => false;
