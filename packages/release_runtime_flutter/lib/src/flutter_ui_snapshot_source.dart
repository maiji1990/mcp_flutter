// packages/release_runtime_flutter/lib/src/flutter_ui_snapshot_source.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart'
    show SemanticSnapshotFilter, SemanticSnapshotService;

/// [ReleaseUiSnapshotSource] backed by the toolkit's semantic snapshot walk.
///
/// This is the only Flutter-aware piece of the release runtime: `SemanticsNode`
/// and `RenderView` may only be touched on the UI isolate, so the runtime keeps
/// this behind an interface and every other layer stays platform-neutral.
///
/// Reuse, not a second implementation: the walk itself is
/// `SemanticSnapshotService.buildSemanticSnapshot`, so a ref means the same
/// thing in a release build as in a debug one, and the two paths cannot drift
/// apart.
///
/// What this adapter adds on top:
/// - `sensitive`: nodes whose semantics carry `SemanticsFlag.isObscured`
///   (passwords, one-time codes) are marked so [ReleasePrivacyFilter] masks
///   their text.
/// - `routeName`: whatever the app's [ReleaseRouteProvider] reports.
/// - `capturedAt`: a UTC timestamp for the snapshot envelope.
final class FlutterReleaseUiSnapshotSource implements ReleaseUiSnapshotSource {
  FlutterReleaseUiSnapshotSource({this.routeProvider});

  /// Supplies the route name reported on a snapshot; optional.
  final ReleaseRouteProvider? routeProvider;

  @override
  Future<ReleaseUiSnapshot> captureSnapshot({
    int? maxNodes,
    String? identifierPrefix,
  }) async {
    final filter = SemanticSnapshotFilter(
      identifierPrefix: identifierPrefix,
      maxNodes: maxNodes,
    );
    final raw = await SemanticSnapshotService.buildSemanticSnapshot(
      filter: filter.isEmpty ? null : filter,
    );

    final rawNodes = raw['nodes'];
    final nodes = <ReleaseUiNode>[];
    if (rawNodes is List) {
      for (final entry in rawNodes) {
        if (entry is! Map) {
          continue;
        }
        final node = ReleaseUiNode.fromJson(entry.cast<String, Object?>());
        nodes.add(
          _isObscured(node.ref) ? node.redacted(sensitive: true) : node,
        );
      }
    }

    return ReleaseUiSnapshot(
      snapshotId: '${raw['snapshot_id'] ?? 0}',
      nodes: nodes,
      capturedAt: DateTime.now().toUtc(),
      truncated: raw['truncated'] == true,
      interactionSurface: raw['interactionSurface'] as String?,
      routeName: await _currentRoute(),
    );
  }

  @override
  Future<ReleasePageInfo> readCurrentPage() async {
    // `peek` does not advance the snapshot id stream, so asking which page is
    // showing cannot invalidate refs a client already holds.
    final raw = await SemanticSnapshotService.peekSemanticSnapshot();

    return ReleasePageInfo(
      snapshotId: '${raw['snapshot_id'] ?? 0}',
      capturedAt: DateTime.now().toUtc(),
      routeName: await _currentRoute(),
      interactionSurface: raw['interactionSurface'] as String?,
      nodeCount: raw['nodeCount'] is int ? raw['nodeCount']! as int : 0,
    );
  }

  /// Whether the node behind [ref] holds obscured (password-like) text.
  ///
  /// Read from the live `SemanticsNode` the last snapshot cached, which is why
  /// this runs immediately after the walk: the ref map is only valid until the
  /// next snapshot.
  static bool _isObscured(String ref) {
    if (ref.isEmpty) {
      return false;
    }
    final node = SemanticSnapshotService.resolveRef(ref);
    if (node == null) {
      return false;
    }
    try {
      return node.getSemanticsData().flagsCollection.isObscured;
    } on Object {
      return false;
    }
  }

  Future<String?> _currentRoute() async {
    final provider = routeProvider;
    if (provider == null) {
      return null;
    }
    try {
      return await provider.currentRouteName();
    } on Object {
      // A router that throws must not take the snapshot down with it.
      return null;
    }
  }
}
