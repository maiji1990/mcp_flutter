// packages/release_runtime/test/support/fake_snapshot_source.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';

/// A snapshot source backed by a fixed node list, for tests that should not
/// need Flutter.
final class FakeSnapshotSource implements ReleaseUiSnapshotSource {
  FakeSnapshotSource({
    List<ReleaseUiNode> nodes = const <ReleaseUiNode>[],
    this.routeName,
    this.interactionSurface = 'rich',
    this.idPrefix = 'ui',
    this.fixedCapturedAt,
  }) : _nodes = List<ReleaseUiNode>.of(nodes);

  final List<ReleaseUiNode> _nodes;
  final String? routeName;
  final String? interactionSurface;
  final String idPrefix;
  final DateTime? fixedCapturedAt;

  int captures = 0;

  @override
  Future<ReleaseUiSnapshot> captureSnapshot({
    int? maxNodes,
    String? identifierPrefix,
  }) async {
    captures += 1;
    var nodes = _nodes;
    if (identifierPrefix != null) {
      nodes = nodes
          .where(
            (node) => node.identifier?.startsWith(identifierPrefix) ?? false,
          )
          .toList(growable: false);
    }
    if (maxNodes != null && nodes.length > maxNodes) {
      nodes = nodes.sublist(0, maxNodes);
    }
    return ReleaseUiSnapshot(
      snapshotId: '$idPrefix-$captures',
      nodes: nodes,
      capturedAt: fixedCapturedAt ?? DateTime.utc(2026, 11, 4, 9),
      truncated: nodes.length != _nodes.length,
      interactionSurface: interactionSurface,
      routeName: routeName,
    );
  }

  @override
  Future<ReleasePageInfo> readCurrentPage() async => ReleasePageInfo(
    snapshotId: '$idPrefix-${captures + 1}',
    capturedAt: fixedCapturedAt ?? DateTime.utc(2026, 11, 4, 9),
    routeName: routeName,
    interactionSurface: interactionSurface,
    nodeCount: _nodes.length,
  );
}
