// packages/release_runtime/lib/src/ui/interaction_driver.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

/// What the live UI says about a ref that was issued earlier.
enum ReleaseUiNodeState {
  /// Still attached, on screen, and enabled.
  attached('attached'),

  /// Left the semantics tree (route closed, list rebuilt, node disposed).
  detached('detached'),

  /// Attached but its centre is outside the visible viewport.
  hidden('hidden'),

  /// Attached and visible but disabled.
  disabled('disabled'),

  /// The driver could not tell; callers must not act on it.
  unknown('unknown');

  const ReleaseUiNodeState(this.wireName);

  final String wireName;
}

/// Direction argument of `ui_scroll`.
enum ReleaseScrollDirection {
  up('up'),
  down('down'),
  left('left'),
  right('right');

  const ReleaseScrollDirection(this.wireName);

  final String wireName;

  /// Parses a wire value, or null when it is not a direction.
  static ReleaseScrollDirection? tryParse(String value) {
    final normalized = value.trim().toLowerCase();
    for (final direction in ReleaseScrollDirection.values) {
      if (direction.wireName == normalized) {
        return direction;
      }
    }
    return null;
  }
}

/// Answer of one driver action.
@immutable
final class ReleaseDriverResult {
  const ReleaseDriverResult({
    required this.ok,
    this.error,
    this.details = const <String, Object?>{},
  });

  const ReleaseDriverResult.success({
    Map<String, Object?> details = const <String, Object?>{},
  }) : this(ok: true, details: details);

  const ReleaseDriverResult.failure(
    String this.error, {
    this.details = const <String, Object?>{},
  }) : ok = false;

  /// Whether the action was dispatched.
  final bool ok;

  /// Short, non-sensitive failure token, for example `target_disabled`.
  final String? error;

  /// Extra non-sensitive facts, for example `via: semantic_action`.
  final Map<String, Object?> details;
}

/// The action side of the release runtime.
///
/// The core validates *whether* an action may run (snapshot currency,
/// permission, capabilities); this interface performs it on the UI isolate.
/// Implementations must not throw for ordinary refusals — return
/// [ReleaseDriverResult.failure] so the runtime can map it onto a stable code.
abstract interface class ReleaseUiInteractionDriver {
  /// Whether [snapshotId] is still the app's current snapshot.
  ///
  /// A UI that changed its tree without taking a new snapshot still counts as
  /// current; [inspect] is what catches a node that left the tree.
  Future<bool> isSnapshotCurrent(String snapshotId);

  /// Current state of the node behind [ref].
  Future<ReleaseUiNodeState> inspect(String ref);

  /// Taps the node behind [ref].
  Future<ReleaseDriverResult> tap(String ref);

  /// Replaces the text of the field behind [ref].
  Future<ReleaseDriverResult> setText(String ref, String text);

  /// Scrolls the node behind [ref] (or its scrollable ancestor).
  Future<ReleaseDriverResult> scroll(
    String ref,
    ReleaseScrollDirection direction, {
    double amount,
  });
}
