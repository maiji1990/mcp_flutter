// packages/release_runtime_flutter/lib/src/sensitive_widgets.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:flutter/widgets.dart';

/// Marks a subtree as holding data an agent must never receive.
///
/// The release runtime reads the semantics tree, and semantics has no notion of
/// "this text is a card number". This wrapper adds the missing signal by setting
/// [SemanticsProperties.obscured] — the same flag Flutter sets for
/// `TextField(obscureText: true)` — so the Flutter adapter marks the node
/// `sensitive` and [RedactingPrivacyFilter] masks its `label`, `value`, and
/// `hint`.
///
/// Prefer it over relying on a route name when a single field inside an
/// otherwise shareable screen is private:
///
/// ```dart
/// AgentSensitive(child: Text('Card number 4111 1111 1111 1111'))
/// ```
///
/// It changes semantics only; painting and layout are untouched.
class AgentSensitive extends StatelessWidget {
  const AgentSensitive({super.key, required this.child, this.label});

  /// The subtree to hide from agent reads.
  final Widget child;

  /// Optional semantics label for the wrapper; masked along with the child.
  final String? label;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, obscured: true, label: label, child: child);
}

/// Removes a subtree from the semantics tree entirely.
///
/// Stronger than [AgentSensitive]: the nodes are absent from snapshots, so an
/// agent cannot count, target, or infer them. Use it for data that should not
/// even be addressable (decorative secrets, full account numbers the app never
/// needs exposed). The trade-off is that automated accessibility tools lose the
/// text too — [AgentSensitive] is the better default for form fields.
class ExcludeFromAgent extends StatelessWidget {
  const ExcludeFromAgent({super.key, required this.child});

  /// The subtree to exclude.
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: child);
}
