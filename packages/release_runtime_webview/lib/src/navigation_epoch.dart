// packages/release_runtime_webview/lib/src/navigation_epoch.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0).

/// Tracks page navigation so refs from before a jump are refused.
///
/// A single `onPageFinished` callback is not enough: a SPA changes
/// `location.href` through the History API without a page load. The adapter
/// observes the URL on every capture and action, so both cases increment
/// [value] and a snapshot from the previous page stops being actionable.
final class ReleaseNavigationEpoch {
  ReleaseNavigationEpoch({this.value = 0, this.url});

  /// Monotonic counter. Starts at 0 and only grows.
  int value;

  /// Last URL that was observed, used to detect a change.
  String? url;

  /// Records [nextUrl] and returns the (possibly advanced) epoch.
  int observe(String? nextUrl) {
    if (nextUrl != url) {
      url = nextUrl;
      value += 1;
    }
    return value;
  }
}
