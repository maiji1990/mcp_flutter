// packages/release_runtime/lib/src/web/release_web_source.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0).

import 'release_web_types.dart';

/// The DOM side of the release runtime.
///
/// Implemented by the optional `release_runtime_webview` package (official
/// `webview_flutter` today) or by an app's own adapter. The core never reaches
/// into a WebView itself: a view exists for an agent only because the app
/// registered it, with an explicit origin allow-list.
///
/// Contract for implementations:
/// - Refuse any page whose origin is not registered; return
///   `origin_denied`, never data.
/// - Never execute caller-supplied JavaScript. Only fixed scripts with
///   schema-validated parameters.
/// - Report navigation as an epoch; a ref from an older epoch is `stale_ref`.
/// - Never throw for an ordinary refusal; return a failure token.
abstract interface class ReleaseEmbeddedWebSource {
  /// Views the app registered. Never a scan of the widget tree.
  Future<List<ReleaseWebViewInfo>> listViews();

  /// Captures the DOM of [viewId].
  Future<ReleaseWebCaptureResult> capture({
    required String viewId,
    int maxNodes,
    int maxDepth,
  });

  /// Clicks the element behind [ref], which must belong to [snapshotId].
  Future<ReleaseWebActionResult> click({
    required String viewId,
    required String ref,
    required String snapshotId,
  });

  /// Replaces the text of the control behind [ref].
  Future<ReleaseWebActionResult> setText({
    required String viewId,
    required String ref,
    required String snapshotId,
    required String text,
  });

  /// Scrolls the page (or the control behind [ref]) by [amount] CSS pixels.
  Future<ReleaseWebActionResult> scroll({
    required String viewId,
    required String ref,
    required String snapshotId,
    required String direction,
    double amount,
  });

  /// Current URL and loading state of [viewId].
  Future<ReleaseWebViewState> readState({required String viewId});
}
