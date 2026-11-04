// packages/release_runtime_webview/lib/src/webview_registry.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0).

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';

import 'navigation_epoch.dart';
import 'webview_engine.dart';

/// One WebView the app chose to expose.
final class ReleaseWebViewRegistration {
  ReleaseWebViewRegistration({
    required this.viewId,
    required this.engine,
    required Set<String> allowedOrigins,
    this.privacyPolicy = const ReleaseWebPrivacyPolicy(),
    this.timeout = const Duration(seconds: 5),
    ReleaseNavigationEpoch? navigation,
  }) : allowedOrigins = Set<String>.unmodifiable(allowedOrigins),
       navigation = navigation ?? ReleaseNavigationEpoch();

  /// App-chosen id, for example `order-h5`.
  final String viewId;

  /// Controller wrapper. Never scanned from the widget tree.
  final ReleaseWebViewEngine engine;

  /// Exact `scheme://host[:port]` values the adapter may read.
  final Set<String> allowedOrigins;

  /// Page rules applied by the adapter before anything is returned.
  final ReleaseWebPrivacyPolicy privacyPolicy;

  /// Per-script timeout.
  final Duration timeout;

  /// Navigation counter for this view.
  final ReleaseNavigationEpoch navigation;
}

/// The app's explicit list of agent-readable WebViews.
///
/// Nothing is discoverable by default: a controller exists for the runtime only
/// because `register` was called with an id and an origin allow-list. That is
/// the whole security boundary — unregistered views are invisible, and a
/// registered view whose page leaves its allowed origins is refused.
final class ReleaseWebViewRegistry {
  static final RegExp _viewIdPattern = RegExp(r'^[a-z][a-z0-9._-]{0,63}$');

  final Map<String, ReleaseWebViewRegistration> _byId =
      <String, ReleaseWebViewRegistration>{};

  /// Registers [engine] under [viewId].
  ///
  /// Throws [ArgumentError] for a malformed id, a duplicate id, an empty
  /// allow-list, or an origin that is not an exact HTTP(S) origin. [allowHttp]
  /// exists for local staging only; production pages should be HTTPS.
  ReleaseWebViewRegistration register({
    required String viewId,
    required ReleaseWebViewEngine engine,
    required Iterable<String> allowedOrigins,
    ReleaseWebPrivacyPolicy privacyPolicy = const ReleaseWebPrivacyPolicy(),
    Duration timeout = const Duration(seconds: 5),
    bool allowHttp = false,
  }) {
    if (!_viewIdPattern.hasMatch(viewId)) {
      throw ArgumentError.value(viewId, 'viewId', 'invalid view id');
    }
    if (_byId.containsKey(viewId)) {
      throw ArgumentError.value(viewId, 'viewId', 'already registered');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    final origins = <String>{};
    for (final origin in allowedOrigins) {
      final normalized = _normalizeOrigin(origin, allowHttp: allowHttp);
      if (normalized == null) {
        throw ArgumentError.value(origin, 'allowedOrigins', 'invalid origin');
      }
      origins.add(normalized);
    }
    if (origins.isEmpty) {
      throw ArgumentError.value(
        allowedOrigins,
        'allowedOrigins',
        'at least one origin is required',
      );
    }

    final registration = ReleaseWebViewRegistration(
      viewId: viewId,
      engine: engine,
      allowedOrigins: origins,
      privacyPolicy: privacyPolicy,
      timeout: timeout,
    );
    _byId[viewId] = registration;
    return registration;
  }

  /// Removes [viewId]; no-op when it was never registered.
  void unregister(String viewId) {
    _byId.remove(viewId);
  }

  /// Registration for [viewId], or null.
  ReleaseWebViewRegistration? registrationFor(String viewId) => _byId[viewId];

  /// Registered views, in registration order.
  List<ReleaseWebViewRegistration> get registrations =>
      List<ReleaseWebViewRegistration>.unmodifiable(_byId.values);

  /// True when nothing is registered.
  bool get isEmpty => _byId.isEmpty;

  /// Exact origin, or null when [value] is not one.
  static String? _normalizeOrigin(String value, {required bool allowHttp}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    if (uri.scheme != 'https' && !(allowHttp && uri.scheme == 'http')) {
      return null;
    }
    if (uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final buffer = StringBuffer('${uri.scheme}://${uri.host}');
    if (uri.hasPort) {
      buffer.write(':${uri.port}');
    }
    return buffer.toString();
  }
}
