// packages/release_runtime/lib/src/web/release_web_types.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0): the WebView seam.
//
// A WebView is not a Flutter subtree. Its DOM lives in a separate browser
// engine, so the Flutter semantics walk cannot see `button`, `input`, or
// `table`. These types are the platform-neutral vocabulary the core tools and
// the optional `release_runtime_webview` adapter share.

import 'package:meta/meta.dart';

import '../ui/release_ui_types.dart';

/// Origin (`scheme://host[:port]`) of [url], or null when it is not absolute.
String? webOriginOf(String? url) {
  if (url == null) {
    return null;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }
  final buffer = StringBuffer('${uri.scheme}://${uri.host}');
  if (uri.hasPort) {
    buffer.write(':${uri.port}');
  }
  return buffer.toString();
}

/// URL as it may be shown to a client: origin plus path, never query, fragment,
/// user info, or credential-looking parameters.
String sanitizeWebUrl(String? url) {
  if (url == null) {
    return '';
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return '';
  }
  final origin = webOriginOf(url);
  final path = uri.path.isEmpty ? '/' : uri.path;
  return '$origin$path';
}

/// One interactive element of a captured DOM.
@immutable
final class ReleaseWebNode {
  const ReleaseWebNode({
    required this.ref,
    required this.tag,
    this.role = '',
    this.inputType = '',
    this.label,
    this.text,
    this.value,
    this.placeholder,
    this.disabled = false,
    this.checked,
    this.sensitive = false,
    this.bounds,
  });

  /// Reads one node from the adapter's JSON.
  factory ReleaseWebNode.fromJson(Map<String, Object?> json) {
    ReleaseUiRect? bounds;
    final rawBounds = json['rect'];
    if (rawBounds is Map) {
      final x = _readDouble(rawBounds['x']);
      final y = _readDouble(rawBounds['y']);
      final width = _readDouble(rawBounds['width']);
      final height = _readDouble(rawBounds['height']);
      bounds = ReleaseUiRect(
        left: x,
        top: y,
        right: x + width,
        bottom: y + height,
      );
    }
    String? text(String key) {
      final value = json[key];
      return value is String ? value : null;
    }

    bool? flag(String key) {
      final value = json[key];
      return value is bool ? value : null;
    }

    return ReleaseWebNode(
      ref: json['ref'] as String? ?? '',
      tag: json['tag'] as String? ?? 'unknown',
      role: text('role') ?? '',
      inputType: text('type') ?? '',
      label: text('label'),
      text: text('text'),
      value: text('value'),
      placeholder: text('placeholder'),
      disabled: flag('disabled') ?? false,
      checked: flag('checked'),
      sensitive: flag('sensitive') ?? false,
      bounds: bounds,
    );
  }

  /// Opaque, snapshot-scoped reference. Never a CSS selector.
  final String ref;

  /// HTML tag name, lowercase.
  final String tag;

  /// ARIA role, when the page declares one.
  final String role;

  /// `input` type, when the node is an input.
  final String inputType;

  /// Accessible name (`aria-label`, associated `label`, ...).
  final String? label;

  /// Short visible text, for non-input nodes.
  final String? text;

  /// Current value, for form controls. Never a password value.
  final String? value;

  /// Placeholder text, for form controls.
  final String? placeholder;

  final bool disabled;

  /// Checked state, for checkboxes and radios.
  final bool? checked;

  /// Whether the element is marked (or recognized) as holding private data.
  final bool sensitive;

  /// Element rectangle in CSS pixels of the page viewport.
  final ReleaseUiRect? bounds;

  /// Returns a copy with text fields replaced; structural fields are kept.
  ReleaseWebNode redacted({String maskMarker = '••••', bool? sensitive}) =>
      ReleaseWebNode(
        ref: ref,
        tag: tag,
        role: role,
        inputType: inputType,
        label: label == null ? null : maskMarker,
        text: text == null ? null : maskMarker,
        value: value == null ? null : maskMarker,
        placeholder: placeholder == null ? null : maskMarker,
        disabled: disabled,
        checked: checked,
        sensitive: sensitive ?? this.sensitive,
        bounds: bounds,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'ref': ref,
    'tag': tag,
    if (role.isNotEmpty) 'role': role,
    if (inputType.isNotEmpty) 'type': inputType,
    if (label != null) 'label': label,
    if (text != null) 'text': text,
    if (value != null) 'value': value,
    if (placeholder != null) 'placeholder': placeholder,
    if (disabled) 'disabled': true,
    if (checked != null) 'checked': checked,
    if (sensitive) 'sensitive': true,
    if (bounds != null) 'rect': bounds!.toJson(),
  };

  static double _readDouble(Object? value) =>
      value is num ? value.toDouble() : 0;
}

/// One captured DOM.
@immutable
final class ReleaseWebDomSnapshot {
  ReleaseWebDomSnapshot({
    required this.viewId,
    required this.snapshotId,
    required this.capturedAt,
    required List<ReleaseWebNode> nodes,
    this.url = '',
    this.title,
    this.origin,
    this.navigationEpoch = 0,
    this.truncated = false,
  }) : nodes = List<ReleaseWebNode>.unmodifiable(nodes);

  /// Registered id of the WebView this came from.
  final String viewId;

  /// Id a client must echo when it acts on a [ReleaseWebNode.ref].
  final String snapshotId;

  /// UTC capture time.
  final DateTime capturedAt;

  /// Nodes in DOM order.
  final List<ReleaseWebNode> nodes;

  /// Already-sanitized page URL (origin + path).
  final String url;

  /// Page title, when the page has one.
  final String? title;

  /// Origin of the page, when known.
  final String? origin;

  /// Adapter navigation counter. A ref from another epoch is stale.
  final int navigationEpoch;

  /// Whether a node or depth budget cut the walk short.
  final bool truncated;

  int get nodeCount => nodes.length;

  ReleaseWebDomSnapshot copyWith({
    List<ReleaseWebNode>? nodes,
    bool? truncated,
    String? url,
  }) => ReleaseWebDomSnapshot(
    viewId: viewId,
    snapshotId: snapshotId,
    capturedAt: capturedAt,
    nodes: nodes ?? this.nodes,
    url: url ?? this.url,
    title: title,
    origin: origin ?? webOriginOf(this.url),
    navigationEpoch: navigationEpoch,
    truncated: truncated ?? this.truncated,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'viewId': viewId,
    'snapshotId': snapshotId,
    'capturedAt': capturedAt.toIso8601String(),
    'url': url,
    // The page title is page-authored text and can quote user data; it stays
    // on the adapter side and never enters the agent payload.
    if (origin != null) 'origin': origin,
    'navigationEpoch': navigationEpoch,
    'nodeCount': nodeCount,
    'truncated': truncated,
    'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
  };
}

/// A WebView the app registered, as exposed by `web_list_views`.
@immutable
final class ReleaseWebViewInfo {
  const ReleaseWebViewInfo({
    required this.viewId,
    this.allowedOrigins = const <String>{},
    this.url,
    this.title,
  });

  final String viewId;
  final Set<String> allowedOrigins;

  /// Sanitized current URL, when the adapter could read it.
  final String? url;
  final String? title;

  Map<String, Object?> toJson() => <String, Object?>{
    'viewId': viewId,
    'allowedOrigins': allowedOrigins.toList(growable: false)..sort(),
    if (url != null) 'url': sanitizeWebUrl(url),
  };
}

/// Loading/navigation state of one registered WebView.
@immutable
final class ReleaseWebViewState {
  const ReleaseWebViewState({
    required this.viewId,
    this.url = '',
    this.title,
    this.origin,
    this.navigationEpoch = 0,
    this.loading = false,
  });

  final String viewId;
  final String url;
  final String? title;
  final String? origin;
  final int navigationEpoch;
  final bool loading;

  Map<String, Object?> toJson() => <String, Object?>{
    'viewId': viewId,
    'url': sanitizeWebUrl(url),
    if (origin != null) 'origin': origin,
    'navigationEpoch': navigationEpoch,
    'loading': loading,
  };
}

/// Answer of one DOM action.
@immutable
final class ReleaseWebActionResult {
  const ReleaseWebActionResult({
    required this.ok,
    this.error,
    this.details = const <String, Object?>{},
  });

  const ReleaseWebActionResult.success({
    this.details = const <String, Object?>{},
  }) : ok = true,
       error = null;

  const ReleaseWebActionResult.failure(
    String this.error, {
    this.details = const <String, Object?>{},
  }) : ok = false;

  final bool ok;

  /// Stable failure token, for example `stale_ref` or `origin_denied`.
  final String? error;

  /// Non-sensitive breadcrumbs.
  final Map<String, Object?> details;
}

/// Answer of a DOM capture.
@immutable
final class ReleaseWebCaptureResult {
  const ReleaseWebCaptureResult.ok(ReleaseWebDomSnapshot this.snapshot)
    : error = null,
      details = const <String, Object?>{};

  const ReleaseWebCaptureResult.failure(
    String this.error, {
    this.details = const <String, Object?>{},
  }) : snapshot = null;

  final ReleaseWebDomSnapshot? snapshot;
  final String? error;
  final Map<String, Object?> details;

  /// True when [snapshot] is present.
  bool get ok => snapshot != null;
}
