// packages/release_runtime_webview/lib/src/webview_flutter_engine.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0).

import 'package:webview_flutter/webview_flutter.dart';

import 'webview_engine.dart';

/// [ReleaseWebViewEngine] backed by the official `webview_flutter` controller.
///
/// No JavaScript channel and no `addJavascriptInterface`: the runtime only
/// calls `runJavaScriptReturningResult` with scripts this package builds. That
/// keeps the page's own content from pushing data into the app, which is the
/// documented Android native-bridge risk this design avoids.
final class WebViewFlutterEngine implements ReleaseWebViewEngine {
  const WebViewFlutterEngine(this.controller);

  /// The controller the app already owns.
  final WebViewController controller;

  @override
  Future<String?> currentUrl() => controller.currentUrl();

  @override
  Future<Object?> runJavaScript(String script) =>
      controller.runJavaScriptReturningResult(script);
}
