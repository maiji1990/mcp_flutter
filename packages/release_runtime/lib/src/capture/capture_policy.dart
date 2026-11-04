// packages/release_runtime/lib/src/capture/capture_policy.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

/// Which routes may be captured.
///
/// Screenshots are all-or-nothing: unlike node text, pixels cannot be redacted
/// after the fact, so a route that shows secrets has to be refused before the
/// frame is taken. The default allows everything and blocks nothing — an app
/// that shows money, health data, or credentials is expected to list those
/// routes here.
@immutable
final class ReleaseCapturePolicy {
  const ReleaseCapturePolicy({
    this.blockedRoutes = const <String>{},
    this.allowWhenRouteUnknown = true,
  });

  /// Route names that must never be captured.
  final Set<String> blockedRoutes;

  /// What to do when the app reports no route name.
  ///
  /// True (default) keeps capture usable for apps without a router; an app that
  /// cannot name its routes and still shows secrets should set this to false.
  final bool allowWhenRouteUnknown;

  /// Whether [routeName] may be captured.
  bool allows(String? routeName) {
    final route = routeName?.trim();
    if (route == null || route.isEmpty) {
      return allowWhenRouteUnknown;
    }
    return !blockedRoutes.contains(route);
  }
}
