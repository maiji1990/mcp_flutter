// packages/release_runtime_webview/lib/src/webview_engine.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0).

/// The two controller operations the DOM adapter needs.
///
/// Narrow on purpose: the adapter cannot call `addJavascriptInterface`, inject
/// an arbitrary script, read cookies, or navigate. Implementations wrap one
/// controller; tests implement this interface without a platform plugin.
abstract interface class ReleaseWebViewEngine {
  /// Current page URL, or null when the controller has not loaded one.
  Future<String?> currentUrl();

  /// Runs one *fixed* adapter script and returns its result.
  ///
  /// `webview_flutter` returns a `String` on Android and a decoded value on
  /// some platforms; the adapter tolerates both.
  Future<Object?> runJavaScript(String script);
}
