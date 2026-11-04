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
/// frame is taken.
///
/// The default is **deny**: [allowedRoutes] is empty, so nothing is capturable
/// until the app names the screens that are safe. That keeps a new integration
/// from shipping a screenshot tool by accident. [blockedRoutes] still wins over
/// [allowedRoutes], so an app can allow a section and refuse one screen inside
/// it.
@immutable
final class ReleaseCapturePolicy {
  const ReleaseCapturePolicy({
    this.allowedRoutes = const <String>{},
    this.blockedRoutes = const <String>{},
    this.allowWhenRouteUnknown = false,
  });

  /// Explicit allow-list. Empty means "no route may be captured".
  final Set<String> allowedRoutes;

  /// Route names that must never be captured, whatever the allow-list says.
  final Set<String> blockedRoutes;

  /// What to do when the app reports no route name.
  ///
  /// False by default: an app that cannot name its routes cannot prove the
  /// screen is safe, so capture is refused.
  final bool allowWhenRouteUnknown;

  /// Whether [routeName] may be captured.
  bool allows(String? routeName) {
    final route = _normalize(routeName);
    if (route == null) {
      return allowWhenRouteUnknown;
    }
    if (blockedRoutes.contains(route)) {
      return false;
    }
    return allowedRoutes.contains(route);
  }

  /// True when the policy has no allow-list at all, so capture is disabled.
  bool get isDenyAll => allowedRoutes.isEmpty && !allowWhenRouteUnknown;

  /// Copy with additional rules.
  ReleaseCapturePolicy merge(ReleaseCapturePolicy other) =>
      ReleaseCapturePolicy(
        allowedRoutes: <String>{...allowedRoutes, ...other.allowedRoutes},
        blockedRoutes: <String>{...blockedRoutes, ...other.blockedRoutes},
        allowWhenRouteUnknown:
            allowWhenRouteUnknown || other.allowWhenRouteUnknown,
      );

  static String? _normalize(String? routeName) {
    if (routeName == null) {
      return null;
    }
    final trimmed = routeName.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
