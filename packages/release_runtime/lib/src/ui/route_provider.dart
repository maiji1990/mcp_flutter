// packages/release_runtime/lib/src/ui/route_provider.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

/// Supplies the route/page name the app is showing.
///
/// A callback interface, not a Navigator hook: an app on `go_router`, a custom
/// `RouterDelegate`, or plain `Navigator` 1.0 wires whatever it already knows.
/// The runtime never guesses a route from the widget tree.
abstract interface class ReleaseRouteProvider {
  /// Current route name, or null when the app has none to report.
  Future<String?> currentRouteName();
}

/// [ReleaseRouteProvider] backed by a function, for apps whose router exposes a
/// synchronous read.
final class CallbackReleaseRouteProvider implements ReleaseRouteProvider {
  const CallbackReleaseRouteProvider(this._read);

  final Future<String?> Function() _read;

  @override
  Future<String?> currentRouteName() => _read();
}
