// packages/release_runtime/lib/src/tools/snapshot_store.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'dart:collection';

import '../ui/release_ui_types.dart';

/// Keeps the snapshots a client may still act on.
///
/// A ref is only meaningful inside the snapshot that issued it, so two facts
/// have to be remembered: which snapshot is current, and whether it has already
/// been used by an interaction. Once a tool acts, the tree may have changed
/// under the refs — consuming the snapshot forces the client to read again
/// before acting a second time instead of clicking whatever took the node's
/// place.
final class ReleaseSnapshotStore {
  ReleaseSnapshotStore({this.capacity = 4});

  /// How many past snapshots are kept for diagnostics; only the latest is
  /// actionable.
  final int capacity;

  final LinkedHashMap<String, ReleaseUiSnapshot> _snapshots =
      LinkedHashMap<String, ReleaseUiSnapshot>();
  final Set<String> _consumed = <String>{};
  String? _latestId;

  /// Snapshot an interaction may currently reference, or null.
  String? get latestId => _latestId;

  /// Number of snapshots retained.
  int get length => _snapshots.length;

  /// True when [snapshotId] is the current, unused snapshot.
  bool isUsable(String snapshotId) =>
      _latestId == snapshotId && !_consumed.contains(snapshotId);

  /// True when the id was issued by this store, current or not.
  bool contains(String snapshotId) => _snapshots.containsKey(snapshotId);

  /// Records [snapshot] and makes it the actionable one.
  String publish(ReleaseUiSnapshot snapshot) {
    _snapshots[snapshot.snapshotId] = snapshot;
    _consumed.remove(snapshot.snapshotId);
    _latestId = snapshot.snapshotId;

    while (_snapshots.length > capacity) {
      final oldest = _snapshots.keys.first;
      _snapshots.remove(oldest);
      _consumed.remove(oldest);
      if (_latestId == oldest) {
        _latestId = null;
      }
    }

    return snapshot.snapshotId;
  }

  /// The stored snapshot [snapshotId], if still retained.
  ReleaseUiSnapshot? snapshotFor(String snapshotId) => _snapshots[snapshotId];

  /// The node [ref] named in [snapshotId], if both are still retained.
  ReleaseUiNode? nodeById(String snapshotId, String ref) {
    final snapshot = _snapshots[snapshotId];
    if (snapshot == null) {
      return null;
    }
    for (final node in snapshot.nodes) {
      if (node.ref == ref) {
        return node;
      }
    }
    return null;
  }

  /// Marks the current snapshot as used, so a second interaction needs a fresh
  /// read.
  void consumeLatest() {
    final latest = _latestId;
    if (latest != null) {
      _consumed.add(latest);
    }
  }

  /// Forgets everything, for tests or a full reset.
  void clear() {
    _snapshots.clear();
    _consumed.clear();
    _latestId = null;
  }
}
