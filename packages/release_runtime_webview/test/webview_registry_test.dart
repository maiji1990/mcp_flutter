// packages/release_runtime_webview/test/webview_registry_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:flutter_mcp_toolkit_release_webview/flutter_mcp_toolkit_release_webview.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Engine implements ReleaseWebViewEngine {
  _Engine({this.url = 'https://app.example.com/orders'});

  String? url;

  @override
  Future<String?> currentUrl() async => url;

  @override
  Future<Object?> runJavaScript(String script) async => null;
}

void main() {
  test('registers a view with an exact origin allow-list', () {
    final registry = ReleaseWebViewRegistry();

    final registration = registry.register(
      viewId: 'orders',
      engine: _Engine(),
      allowedOrigins: const <String>['https://app.example.com'],
    );

    expect(registration.viewId, 'orders');
    expect(registration.allowedOrigins, <String>{'https://app.example.com'});
    expect(registry.registrationFor('orders'), same(registration));
    expect(registry.registrations, hasLength(1));
  });

  test('rejects an empty or non-https allow-list by default', () {
    final registry = ReleaseWebViewRegistry();

    expect(
      () => registry.register(
        viewId: 'orders',
        engine: _Engine(),
        allowedOrigins: const <String>[],
      ),
      throwsArgumentError,
    );
    expect(
      () => registry.register(
        viewId: 'orders',
        engine: _Engine(),
        allowedOrigins: const <String>['http://app.example.com'],
      ),
      throwsArgumentError,
    );
    expect(
      () => registry.register(
        viewId: 'orders',
        engine: _Engine(),
        allowedOrigins: const <String>['https://app.example.com/path'],
      ),
      throwsArgumentError,
    );
  });

  test('allowHttp is an explicit opt-in for local staging', () {
    final registry = ReleaseWebViewRegistry();

    final registration = registry.register(
      viewId: 'staging',
      engine: _Engine(url: 'http://10.0.2.2:8080/orders'),
      allowedOrigins: const <String>['http://10.0.2.2:8080'],
      allowHttp: true,
    );

    expect(registration.allowedOrigins, <String>{'http://10.0.2.2:8080'});
  });

  test('rejects duplicate ids and malformed ids', () {
    final registry = ReleaseWebViewRegistry()
      ..register(
        viewId: 'orders',
        engine: _Engine(),
        allowedOrigins: const <String>['https://app.example.com'],
      );

    expect(
      () => registry.register(
        viewId: 'orders',
        engine: _Engine(),
        allowedOrigins: const <String>['https://app.example.com'],
      ),
      throwsArgumentError,
    );
    expect(
      () => registry.register(
        viewId: 'Orders H5',
        engine: _Engine(),
        allowedOrigins: const <String>['https://app.example.com'],
      ),
      throwsArgumentError,
    );
  });

  test('unregister removes the view', () {
    final registry = ReleaseWebViewRegistry()
      ..register(
        viewId: 'orders',
        engine: _Engine(),
        allowedOrigins: const <String>['https://app.example.com'],
      )
      ..unregister('orders');

    expect(registry.isEmpty, isTrue);
    expect(registry.registrationFor('orders'), isNull);
  });

  test('a registration carries the page privacy policy', () {
    final registry = ReleaseWebViewRegistry()
      ..register(
        viewId: 'orders',
        engine: _Engine(),
        allowedOrigins: const <String>['https://app.example.com'],
        privacyPolicy: const ReleaseWebPrivacyPolicy(
          deniedPathPrefixes: <String>{'/account'},
        ),
      );

    expect(
      registry
          .registrationFor('orders')!
          .privacyPolicy
          .allowsUrl('https://app.example.com/account/security'),
      isFalse,
    );
  });
}
