// packages/release_runtime_webview/test/webview_dom_source_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'dart:convert';

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:flutter_mcp_toolkit_release_webview/flutter_mcp_toolkit_release_webview.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeEngine implements ReleaseWebViewEngine {
  _FakeEngine({this.url = 'https://app.example.com/orders'});

  String? url;
  Object? Function(String script)? onRun;
  final List<String> scripts = <String>[];

  @override
  Future<String?> currentUrl() async => url;

  @override
  Future<Object?> runJavaScript(String script) async {
    scripts.add(script);
    return onRun?.call(script);
  }
}

String _snapshotJson({
  String origin = 'https://app.example.com',
  String href = 'https://app.example.com/orders',
  List<Map<String, Object?>>? nodes,
}) => jsonEncode(<String, Object?>{
  'origin': origin,
  'href': href,
  'title': 'Orders',
  'nonce': 'n1',
  'truncated': false,
  'nodes':
      nodes ??
      <Map<String, Object?>>[
        <String, Object?>{
          'ref': 'w1_0',
          'tag': 'button',
          'role': 'button',
          'label': 'Search',
          'text': 'Search',
          'rect': <String, Object?>{'x': 0, 'y': 0, 'width': 10, 'height': 10},
        },
        <String, Object?>{
          'ref': 'w1_1',
          'tag': 'input',
          'type': 'password',
          'label': 'Password',
          'value': 'hunter2',
          'sensitive': true,
          'rect': <String, Object?>{'x': 0, 'y': 40, 'width': 10, 'height': 10},
        },
      ],
});

ReleaseWebViewRegistry _registry(_FakeEngine engine) {
  return ReleaseWebViewRegistry()..register(
    viewId: 'orders',
    engine: engine,
    allowedOrigins: const <String>['https://app.example.com'],
  );
}

void main() {
  group('capture', () {
    test('parses nodes and redacts password values', () async {
      final engine = _FakeEngine()..onRun = (script) => _snapshotJson();
      final source = WebViewDomReleaseSource(_registry(engine));

      final result = await source.capture(viewId: 'orders');

      expect(result.ok, isTrue, reason: result.error);
      final snapshot = result.snapshot!;
      expect(snapshot.nodes, hasLength(2));
      expect(snapshot.snapshotId, startsWith('web:orders:1:'));
      expect(snapshot.url, 'https://app.example.com/orders');
      final password = snapshot.nodes.firstWhere(
        (node) => node.inputType == 'password',
      );
      expect(password.value, '••••');
      expect(password.label, '••••');
      expect(password.sensitive, isTrue);
      expect(snapshot.toJson().toString(), isNot(contains('hunter2')));
    });

    test('unwraps the double-encoded result Android returns', () async {
      // `evaluateJavascript` returns the JSON text of the script's string
      // result, so a `JSON.stringify` script arrives quoted twice.
      final engine = _FakeEngine()
        ..onRun = (script) => jsonEncode(_snapshotJson());
      final source = WebViewDomReleaseSource(_registry(engine));

      final result = await source.capture(viewId: 'orders');

      expect(result.ok, isTrue, reason: result.error);
      expect(result.snapshot!.nodes, hasLength(2));
    });

    test('refuses a page outside the registered origins', () async {
      final engine = _FakeEngine(url: 'https://evil.example.com/orders');
      final source = WebViewDomReleaseSource(_registry(engine));

      final result = await source.capture(viewId: 'orders');

      expect(result.ok, isFalse);
      expect(result.error, 'origin_denied');
      expect(engine.scripts, isEmpty);
    });

    test('refuses an unregistered view', () async {
      final source = WebViewDomReleaseSource(ReleaseWebViewRegistry());

      final result = await source.capture(viewId: 'orders');

      expect(result.error, 'view_not_found');
    });

    test('a SPA navigation during capture moves the snapshot epoch', () async {
      final engine = _FakeEngine()
        ..onRun = (script) =>
            _snapshotJson(href: 'https://app.example.com/checkout');
      final source = WebViewDomReleaseSource(_registry(engine));

      final result = await source.capture(viewId: 'orders');

      expect(result.ok, isTrue, reason: result.error);
      expect(result.snapshot!.url, 'https://app.example.com/checkout');
      expect(result.snapshot!.navigationEpoch, 1);
      expect(result.snapshot!.snapshotId, startsWith('web:orders:1:'));
    });

    test('a denied path is refused by the registration policy', () async {
      final engine = _FakeEngine()..onRun = (script) => _snapshotJson();
      final registry = ReleaseWebViewRegistry()
        ..register(
          viewId: 'orders',
          engine: engine,
          allowedOrigins: const <String>['https://app.example.com'],
          privacyPolicy: const ReleaseWebPrivacyPolicy(
            deniedPathPrefixes: <String>{'/orders'},
          ),
        );
      final source = WebViewDomReleaseSource(registry);

      final result = await source.capture(viewId: 'orders');

      expect(result.error, 'path_denied');
    });

    test('a malformed script result is a failure, not a crash', () async {
      final engine = _FakeEngine()..onRun = (script) => 'not json';
      final source = WebViewDomReleaseSource(_registry(engine));

      final result = await source.capture(viewId: 'orders');

      expect(result.error, 'script_failed');
    });
  });

  group('actions', () {
    test('click uses the snapshot nonce and reports success', () async {
      final engine = _FakeEngine()..onRun = (script) => _snapshotJson();
      final source = WebViewDomReleaseSource(_registry(engine));
      final capture = await source.capture(viewId: 'orders');

      engine.onRun = (script) => jsonEncode(<String, Object?>{
        'ok': true,
        'href': 'https://app.example.com/orders',
      });
      final result = await source.click(
        viewId: 'orders',
        ref: 'w1_0',
        snapshotId: capture.snapshot!.snapshotId,
      );

      expect(result.ok, isTrue, reason: result.error);
      expect(engine.scripts.last, contains('"w1_0"'));
      expect(engine.scripts.last, contains('el.click()'));
    });

    test('a snapshot from another epoch is refused', () async {
      final engine = _FakeEngine()..onRun = (script) => _snapshotJson();
      final source = WebViewDomReleaseSource(_registry(engine));
      await source.capture(viewId: 'orders');

      final result = await source.click(
        viewId: 'orders',
        ref: 'w1_0',
        snapshotId: 'web:orders:0:oldnonce',
      );

      expect(result.ok, isFalse);
      expect(result.error, 'navigation_changed');
    });

    test('the page can refuse an action after a SPA navigation', () async {
      final engine = _FakeEngine()..onRun = (script) => _snapshotJson();
      final source = WebViewDomReleaseSource(_registry(engine));
      final capture = await source.capture(viewId: 'orders');

      // The page script compares `store.href` with `location.href`; a
      // pushState between snapshot and action is refused there, because the
      // controller's reported URL can lag the History change.
      engine.onRun = (script) =>
          jsonEncode(<String, Object?>{'error': 'navigation_changed'});
      final result = await source.click(
        viewId: 'orders',
        ref: 'w1_0',
        snapshotId: capture.snapshot!.snapshotId,
      );

      expect(result.ok, isFalse);
      expect(result.error, 'navigation_changed');
    });

    test('a page that leaves the origin is refused before dispatch', () async {
      final engine = _FakeEngine()..onRun = (script) => _snapshotJson();
      final source = WebViewDomReleaseSource(_registry(engine));
      final capture = await source.capture(viewId: 'orders');

      engine.url = 'https://evil.example.com/orders';
      final result = await source.click(
        viewId: 'orders',
        ref: 'w1_0',
        snapshotId: capture.snapshot!.snapshotId,
      );

      expect(result.error, 'origin_denied');
    });

    test(
      'an action that navigates reports it and advances the epoch',
      () async {
        final engine = _FakeEngine()..onRun = (script) => _snapshotJson();
        final registry = _registry(engine);
        final source = WebViewDomReleaseSource(registry);
        final capture = await source.capture(viewId: 'orders');

        engine.onRun = (script) => jsonEncode(<String, Object?>{
          'ok': true,
          'href': 'https://app.example.com/checkout',
        });
        final result = await source.click(
          viewId: 'orders',
          ref: 'w1_0',
          snapshotId: capture.snapshot!.snapshotId,
        );

        expect(result.ok, isTrue, reason: result.error);
        expect(result.details['navigated'], isTrue);
        expect(result.details['url'], 'https://app.example.com/checkout');
        expect(registry.registrationFor('orders')!.navigation.value, 2);
      },
    );

    test('a page-side refusal token is returned verbatim', () async {
      final engine = _FakeEngine()..onRun = (script) => _snapshotJson();
      final source = WebViewDomReleaseSource(_registry(engine));
      final capture = await source.capture(viewId: 'orders');

      engine.onRun = (script) =>
          jsonEncode(<String, Object?>{'error': 'target_sensitive'});
      final result = await source.setText(
        viewId: 'orders',
        ref: 'w1_1',
        snapshotId: capture.snapshot!.snapshotId,
        text: 'guess',
      );

      expect(result.error, 'target_sensitive');
    });
  });

  group('readState', () {
    test('reports the sanitized URL and epoch', () async {
      final engine = _FakeEngine();
      final source = WebViewDomReleaseSource(_registry(engine));

      final state = await source.readState(viewId: 'orders');

      expect(state.url, 'https://app.example.com/orders');
      expect(state.origin, 'https://app.example.com');
      expect(state.navigationEpoch, 1);
    });

    test('refuses an unregistered view', () async {
      final source = WebViewDomReleaseSource(ReleaseWebViewRegistry());

      expect(
        () => source.readState(viewId: 'orders'),
        throwsA(
          isA<ReleaseMcpException>().having(
            (error) => error.code,
            'code',
            ReleaseMcpErrorCode.viewNotFound,
          ),
        ),
      );
    });
  });
}
