// packages/release_runtime/lib/src/privacy/privacy_filter.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

import '../errors/release_mcp_error.dart';
import '../ui/release_ui_types.dart';
import 'privacy_policy.dart';

/// Result of screening a snapshot.
///
/// Either a snapshot that is safe to serialize, or a refusal with a stable
/// error code. A refusal carries no node text, so a denied page cannot leak
/// through its own error message.
@immutable
final class ReleasePrivacyVerdict {
  const ReleasePrivacyVerdict.allowed(ReleaseUiSnapshot this.snapshot)
    : denialCode = null,
      reason = null;

  const ReleasePrivacyVerdict.denied(String this.denialCode, {this.reason})
    : snapshot = null;

  /// Screened snapshot, or null when [isDenied].
  final ReleaseUiSnapshot? snapshot;

  /// Stable error code when denied.
  final String? denialCode;

  /// Non-sensitive reason token when denied, for example `sensitive_route`.
  final String? reason;

  /// Whether the snapshot must not leave the app.
  bool get isDenied => snapshot == null;
}

/// Last line of defence before a snapshot leaves the app.
///
/// The Flutter adapter flags nodes whose semantics are obscured (password,
/// one-time code). This filter is what actually removes the text: a flag alone
/// would be advisory, and an MCP client reads whatever is in the payload.
///
/// Since PR-07 it also applies [ReleaseUiPrivacyPolicy]: a denied route is
/// refused before any node is serialized, and a sensitive node loses `label`,
/// `value`, and `hint` — not just the value, which an app can accidentally put
/// into the label of a custom widget.
abstract interface class ReleasePrivacyFilter {
  /// Decision for a route, before the snapshot is serialized.
  ReleasePrivacyDecision routeDecision(String? routeName);

  /// Returns a snapshot safe to serialize, or a refusal.
  ReleasePrivacyVerdict screen(ReleaseUiSnapshot snapshot);

  /// Convenience for callers that already checked [routeDecision].
  ReleaseUiSnapshot apply(ReleaseUiSnapshot snapshot);
}

/// Masks sensitive values, optionally every value, and truncates long text.
///
/// Defaults are the safe ones: nodes marked `sensitive` lose `label`, `value`,
/// and `hint`, declared sensitive routes are refused, and long text is
/// truncated so a single node cannot blow the response budget.
final class RedactingPrivacyFilter implements ReleasePrivacyFilter {
  const RedactingPrivacyFilter({
    this.maxTextLength = 160,
    this.maskAllValues = false,
    this.maskMarker = '••••',
    this.policy = const ReleaseUiPrivacyPolicy(),
  });

  /// Longest text kept for label/value/hint; longer text is cut and marked.
  final int maxTextLength;

  /// Mask every text field, not only the sensitive ones.
  final bool maskAllValues;

  /// Replacement text for a masked value.
  final String maskMarker;

  /// Page- and node-level rules applied before masking.
  final ReleaseUiPrivacyPolicy policy;

  /// Effective policy: the constructor flag and the policy flag are OR-ed.
  ReleaseUiPrivacyPolicy get effectivePolicy =>
      maskAllValues && !policy.maskAllValues
      ? policy.merge(const ReleaseUiPrivacyPolicy(maskAllValues: true))
      : policy;

  @override
  ReleasePrivacyDecision routeDecision(String? routeName) =>
      effectivePolicy.routeDecision(routeName);

  @override
  ReleasePrivacyVerdict screen(ReleaseUiSnapshot snapshot) {
    final route = routeDecision(snapshot.routeName);
    if (route == ReleasePrivacyDecision.deny) {
      return const ReleasePrivacyVerdict.denied(
        ReleaseMcpErrorCode.routeDenied,
        reason: 'sensitive_route',
      );
    }

    final policy = effectivePolicy;
    final routeMasks = route == ReleasePrivacyDecision.mask;

    // First pass: find every denied subtree before emitting anything, so a
    // child that appears before its denied parent cannot slip through.
    final removed = <String>{};
    for (final node in snapshot.nodes) {
      final decision = routeMasks
          ? ReleasePrivacyDecision.mask
          : policy.nodeDecision(node);
      if (decision == ReleasePrivacyDecision.deny) {
        _collectSubtree(node, snapshot.nodes, removed);
      }
    }

    final nodes = <ReleaseUiNode>[];
    var redacted = removed.isNotEmpty;

    for (final node in snapshot.nodes) {
      if (node.ref.isNotEmpty && removed.contains(node.ref)) {
        continue;
      }
      final decision = routeMasks
          ? ReleasePrivacyDecision.mask
          : policy.nodeDecision(node);
      if (decision == ReleasePrivacyDecision.deny) {
        continue;
      }
      final masksText = decision == ReleasePrivacyDecision.mask;
      final masksEverything = masksText && policy.maskSensitiveLabels;
      final value = node.value == null
          ? null
          : (masksText ? maskMarker : _truncate(node.value));
      final label = masksEverything ? maskMarker : _truncate(node.label);
      final hint = masksEverything ? maskMarker : _truncate(node.hint);
      final changed =
          value != node.value ||
          label != node.label ||
          hint != node.hint ||
          (masksText && !node.sensitive);
      if (changed) {
        redacted = true;
      }
      nodes.add(
        changed
            ? node.redacted(
                label: label,
                value: value,
                hint: hint,
                sensitive: masksText ? true : null,
              )
            : node,
      );
    }

    if (!redacted && nodes.length == snapshot.nodes.length) {
      return ReleasePrivacyVerdict.allowed(snapshot);
    }
    return ReleasePrivacyVerdict.allowed(
      snapshot.copyWith(nodes: nodes, truncated: snapshot.truncated),
    );
  }

  @override
  ReleaseUiSnapshot apply(ReleaseUiSnapshot snapshot) {
    final verdict = screen(snapshot);
    final screened = verdict.snapshot;
    if (screened == null) {
      // `apply` cannot express a refusal; callers that need one use [screen].
      return ReleaseUiSnapshot(
        snapshotId: snapshot.snapshotId,
        nodes: const <ReleaseUiNode>[],
        capturedAt: snapshot.capturedAt,
        truncated: true,
        routeName: snapshot.routeName,
      );
    }
    return screened;
  }

  String? _truncate(String? text) {
    if (text == null || text.length <= maxTextLength) {
      return text;
    }
    return '${text.substring(0, maxTextLength)}…';
  }

  /// Adds [node]'s ref and every reachable descendant ref to [removed].
  static void _collectSubtree(
    ReleaseUiNode node,
    List<ReleaseUiNode> all,
    Set<String> removed,
  ) {
    final byRef = <String, ReleaseUiNode>{
      for (final candidate in all)
        if (candidate.ref.isNotEmpty) candidate.ref: candidate,
    };
    final pending = <ReleaseUiNode>[node];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (current.ref.isNotEmpty && !removed.add(current.ref)) {
        continue;
      }
      for (final child in current.children) {
        final next = byRef[child];
        if (next != null) {
          pending.add(next);
        }
      }
    }
  }
}
