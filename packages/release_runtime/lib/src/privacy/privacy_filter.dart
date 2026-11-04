// packages/release_runtime/lib/src/privacy/privacy_filter.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import '../ui/release_ui_types.dart';

/// Last line of defence before a snapshot leaves the app.
///
/// The Flutter adapter flags nodes whose semantics are obscured (password,
/// one-time code). This filter is what actually removes the text: a flag alone
/// would be advisory, and an MCP client reads whatever is in the payload.
abstract interface class ReleasePrivacyFilter {
  /// Returns a snapshot safe to serialize.
  ReleaseUiSnapshot apply(ReleaseUiSnapshot snapshot);
}

/// Masks sensitive values, optionally every value, and truncates long text.
///
/// Defaults are the safe ones: only nodes marked `sensitive` are masked, and
/// long labels are truncated so a single node cannot blow the response budget.
/// Set [maskAllValues] when the app's policy is "no field text ever".
final class RedactingPrivacyFilter implements ReleasePrivacyFilter {
  const RedactingPrivacyFilter({
    this.maxTextLength = 160,
    this.maskAllValues = false,
    this.maskMarker = '••••',
  });

  /// Longest text kept for label/value/hint; longer text is cut and marked.
  final int maxTextLength;

  /// Mask every `value`, not only the sensitive ones.
  final bool maskAllValues;

  /// Replacement text for a masked value.
  final String maskMarker;

  @override
  ReleaseUiSnapshot apply(ReleaseUiSnapshot snapshot) {
    var redacted = false;
    final nodes = <ReleaseUiNode>[];

    for (final node in snapshot.nodes) {
      final masksValue = maskAllValues || node.sensitive;
      final value = node.value == null
          ? null
          : (masksValue ? maskMarker : _truncate(node.value));
      final label = _truncate(node.label);
      final hint = _truncate(node.hint);
      final changed =
          value != node.value || label != node.label || hint != node.hint;
      if (changed) {
        redacted = true;
      }
      nodes.add(
        changed ? node.redacted(label: label, value: value, hint: hint) : node,
      );
    }

    return redacted ? snapshot.copyWith(nodes: nodes) : snapshot;
  }

  String? _truncate(String? text) {
    if (text == null || text.length <= maxTextLength) {
      return text;
    }
    return '${text.substring(0, maxTextLength)}…';
  }
}
