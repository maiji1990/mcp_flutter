// packages/release_runtime/lib/src/web/release_web_privacy.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0).

import 'package:meta/meta.dart';

import 'release_web_types.dart';

/// Result of screening a DOM snapshot.
@immutable
final class ReleaseWebScreening {
  const ReleaseWebScreening.allowed(ReleaseWebDomSnapshot this.snapshot)
    : denialReason = null;

  const ReleaseWebScreening.denied(this.denialReason) : snapshot = null;

  final ReleaseWebDomSnapshot? snapshot;

  /// Stable token, for example `path_denied` or `insecure_origin`.
  final String? denialReason;

  bool get isDenied => snapshot == null;
}

/// Page- and node-level rules for DOM snapshots.
///
/// The adapter redacts in JavaScript; this policy is the second, dart-side
/// check, so a buggy or swapped adapter cannot hand a password value to a
/// client. It is deliberately blunt: false positives (masking a search box
/// called `token`) are cheap, a leaked OTP is not.
@immutable
final class ReleaseWebPrivacyPolicy {
  const ReleaseWebPrivacyPolicy({
    this.deniedPathPrefixes = const <String>{},
    this.allowedPathPrefixes = const <String>{},
    this.maskedInputTypes = const <String>{'password', 'email', 'tel'},
    this.maskedRoles = const <String>{},
    this.maskAllValues = false,
    this.allowInsecureHttp = false,
    this.maskMarker = '••••',
    this.maxTextLength = 200,
  });

  /// Paths that may never be read, whatever the origin policy says.
  final Set<String> deniedPathPrefixes;

  /// When non-empty, only these path prefixes may be read.
  final Set<String> allowedPathPrefixes;

  /// Input types whose value is always masked.
  final Set<String> maskedInputTypes;

  /// ARIA roles whose text is always masked.
  final Set<String> maskedRoles;

  /// Mask every value, not only the sensitive ones.
  final bool maskAllValues;

  /// Allow `http://` pages. Staging only: production pages must be HTTPS.
  final bool allowInsecureHttp;

  /// Replacement text.
  final String maskMarker;

  /// Longest text kept for label/text/value/placeholder.
  final int maxTextLength;

  /// Whether [url] may be read at all.
  bool allowsUrl(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return false;
    }
    // HTTPS only: `file://`, `content://`, `javascript:`, and `data:`
    // pages are not app content and have no origin the app can trust. Plain
    // `http://` is allowed only when the app explicitly opts into staging.
    if (uri.scheme != 'https' && !(allowInsecureHttp && uri.scheme == 'http')) {
      return false;
    }
    if (uri.host.isEmpty) {
      return false;
    }
    final path = uri.path.isEmpty ? '/' : uri.path;
    for (final denied in deniedPathPrefixes) {
      if (path.startsWith(denied)) {
        return false;
      }
    }
    if (allowedPathPrefixes.isEmpty) {
      return true;
    }
    for (final allowed in allowedPathPrefixes) {
      if (path.startsWith(allowed)) {
        return true;
      }
    }
    return false;
  }

  /// Applies URL and node rules to [snapshot].
  ReleaseWebScreening screen(ReleaseWebDomSnapshot snapshot) {
    if (!allowsUrl(snapshot.url)) {
      return const ReleaseWebScreening.denied('path_denied');
    }
    return ReleaseWebScreening.allowed(
      snapshot.copyWith(
        nodes: snapshot.nodes
            .map((node) => screenNode(node))
            .toList(growable: false),
      ),
    );
  }

  /// Masks one node when the policy says so.
  ReleaseWebNode screenNode(ReleaseWebNode node) {
    final masks =
        node.sensitive ||
        maskAllValues ||
        maskedInputTypes.contains(node.inputType.toLowerCase()) ||
        maskedRoles.contains(node.role.toLowerCase()) ||
        maskedRoles.contains(node.tag.toLowerCase());
    if (masks) {
      return node.redacted(maskMarker: maskMarker, sensitive: true);
    }
    return ReleaseWebNode(
      ref: node.ref,
      tag: node.tag,
      role: node.role,
      inputType: node.inputType,
      label: _truncate(node.label),
      text: _truncate(node.text),
      value: _truncate(node.value),
      placeholder: _truncate(node.placeholder),
      disabled: node.disabled,
      checked: node.checked,
      sensitive: false,
      bounds: node.bounds,
    );
  }

  String? _truncate(String? text) {
    if (text == null || text.length <= maxTextLength) {
      return text;
    }
    return '${text.substring(0, maxTextLength)}…';
  }
}
