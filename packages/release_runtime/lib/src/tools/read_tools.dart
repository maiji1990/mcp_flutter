// packages/release_runtime/lib/src/tools/read_tools.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import '../errors/release_mcp_error.dart';
import '../privacy/privacy_filter.dart';
import '../security/permissions.dart';
import '../ui/release_ui_types.dart';
import 'release_tools.dart';
import 'snapshot_store.dart';

/// The read-only UI tools of release MCP v1: `ui_get_tree`,
/// `ui_get_current_page`, and `ui_find_element`.
///
/// All three need `ui:read` and none of them changes app state, so a session
/// that was started read-only can use them immediately.
///
/// Budgets are enforced here rather than in the adapter: `maxNodes` is clamped
/// to [maxNodesCeiling] and `maxDepth` to [maxDepthCeiling], so a client cannot
/// ask for a tree large enough to stall the UI isolate.
final class ReleaseReadTools implements ReleaseToolSurface {
  ReleaseReadTools({
    required this.source,
    this.privacy = const RedactingPrivacyFilter(),
    this.store,
    this.maxNodesCeiling = 500,
    this.maxDepthCeiling = 64,
  });

  /// Where snapshots come from (the Flutter adapter in a release app).
  final ReleaseUiSnapshotSource source;

  /// Publish targets, so refs from a read can be used by an interaction.
  ///
  /// When null the tools stay usable read-only; nothing can be clicked, which
  /// is the right default for a runtime that has no interaction driver.
  final ReleaseSnapshotStore? store;

  /// The filter applied before a snapshot leaves the runtime.
  final ReleasePrivacyFilter privacy;

  /// Hard cap on nodes any single call may return.
  final int maxNodesCeiling;

  /// Hard cap on the depth any single call may walk.
  final int maxDepthCeiling;

  int _requestCounter = 0;

  @override
  List<ReleaseToolDefinition> get tools => <ReleaseToolDefinition>[
    ReleaseToolDefinition(
      name: 'ui_get_tree',
      description:
          'Read the app UI tree as a flat list of semantic nodes with stable '
          'refs. Read-only; requires ui:read.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'filter': <String, Object?>{
            'type': 'string',
            'description':
                'Keep only nodes whose identifier starts with this prefix.',
          },
          'maxNodes': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': maxNodesCeiling,
            'description': 'Cap on returned nodes (default 200).',
          },
          'maxDepth': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': maxDepthCeiling,
            'description':
                'Depth from the roots to walk, 0 = roots only (default 64).',
          },
        },
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.uiRead,
    ),
    ReleaseToolDefinition(
      name: 'ui_get_current_page',
      description:
          'Report the page the app is showing: route name when one is wired, '
          'interaction surface, and node count. Read-only; requires ui:read.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.uiRead,
    ),
    ReleaseToolDefinition(
      name: 'ui_find_element',
      description:
          'Find nodes by identifier, label, or role against a fresh snapshot. '
          'Refuses an ambiguous query instead of guessing. Read-only; requires '
          'ui:read.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'identifier': <String, Object?>{'type': 'string'},
          'label': <String, Object?>{'type': 'string'},
          'role': <String, Object?>{'type': 'string'},
        },
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.uiRead,
    ),
  ];

  @override
  Future<ReleaseToolCallResult> call(
    String name,
    Map<String, Object?> arguments,
  ) {
    switch (name) {
      case 'ui_get_tree':
        return _getTree(arguments);
      case 'ui_get_current_page':
        return _getCurrentPage();
      case 'ui_find_element':
        return _findElement(arguments);
      default:
        return Future<ReleaseToolCallResult>.value(
          _failure(
            _nextRequestId(),
            ReleaseMcpErrorCode.toolNotFound,
            'Call tools/list for the catalog.',
          ),
        );
    }
  }

  Future<ReleaseToolCallResult> _getTree(Map<String, Object?> arguments) async {
    final requestId = _nextRequestId();

    final maxNodesResult = _readBoundedInt(
      arguments,
      'maxNodes',
      fallback: 200,
      ceiling: maxNodesCeiling,
    );
    if (maxNodesResult.error != null) {
      return _failure(requestId, 'invalid_argument', maxNodesResult.error!);
    }
    final maxDepthResult = _readBoundedInt(
      arguments,
      'maxDepth',
      fallback: maxDepthCeiling,
      ceiling: maxDepthCeiling,
    );
    if (maxDepthResult.error != null) {
      return _failure(requestId, 'invalid_argument', maxDepthResult.error!);
    }
    final filter = _readString(arguments, 'filter');

    final snapshot = privacy.apply(
      await source.captureSnapshot(identifierPrefix: filter),
    );

    final walkOrder = _withinDepth(snapshot.nodes, maxDepthResult.value!);
    final capped = walkOrder.length > maxNodesResult.value!
        ? walkOrder.sublist(0, maxNodesResult.value!)
        : walkOrder;

    // Publish exactly what the caller can see: a ref the response never
    // contained must not become clickable through a lucky guess.
    store?.publish(snapshot.copyWith(nodes: capped));

    return ReleaseToolCallResult(
      requestId: requestId,
      success: true,
      snapshotId: snapshot.snapshotId,
      data: <String, Object?>{
        'capturedAt': snapshot.capturedAt.toIso8601String(),
        'nodeCount': capped.length,
        'totalNodeCount': snapshot.nodeCount,
        'truncated': snapshot.truncated || capped.length != snapshot.nodeCount,
        if (snapshot.routeName != null) 'routeName': snapshot.routeName,
        if (snapshot.interactionSurface != null)
          'interactionSurface': snapshot.interactionSurface,
        'filter': ?filter,
        'maxNodes': maxNodesResult.value,
        'maxDepth': maxDepthResult.value,
        'nodes': capped.map((node) => node.toJson()).toList(growable: false),
      },
    );
  }

  Future<ReleaseToolCallResult> _getCurrentPage() async {
    final requestId = _nextRequestId();
    final page = await source.readCurrentPage();

    return ReleaseToolCallResult(
      requestId: requestId,
      success: true,
      snapshotId: page.snapshotId,
      data: page.toJson(),
    );
  }

  Future<ReleaseToolCallResult> _findElement(
    Map<String, Object?> arguments,
  ) async {
    final requestId = _nextRequestId();

    final identifier = _readString(arguments, 'identifier');
    final label = _readString(arguments, 'label');
    final role = _readString(arguments, 'role');
    if (identifier == null && label == null && role == null) {
      return _failure(
        requestId,
        'invalid_argument',
        'Pass at least one of identifier, label, or role.',
      );
    }

    final snapshot = privacy.apply(await source.captureSnapshot());
    store?.publish(snapshot);
    final matches = snapshot.nodes
        .where(
          (node) =>
              (identifier == null || node.identifier == identifier) &&
              (label == null ||
                  node.label?.trim().toLowerCase() ==
                      label.trim().toLowerCase()) &&
              (role == null || node.type.toLowerCase() == role.toLowerCase()),
        )
        .toList(growable: false);

    if (matches.isEmpty) {
      return _failure(
        requestId,
        'element_not_found',
        'No node matches the query.',
        snapshotId: snapshot.snapshotId,
        details: <String, Object?>{'nodeCount': snapshot.nodeCount},
      );
    }
    if (matches.length > 1) {
      return _failure(
        requestId,
        'ambiguous_match',
        'More than one node matches; narrow the query with an identifier or '
            'role.',
        snapshotId: snapshot.snapshotId,
        details: <String, Object?>{
          'matchCount': matches.length,
          'refs': matches.map((node) => node.ref).toList(growable: false),
          'types': matches
              .map((node) => node.type)
              .toSet()
              .toList(growable: false),
        },
      );
    }

    return ReleaseToolCallResult(
      requestId: requestId,
      success: true,
      snapshotId: snapshot.snapshotId,
      data: <String, Object?>{'matchCount': 1, 'node': matches.single.toJson()},
    );
  }

  /// Keeps nodes up to [maxDepth] from the roots, in walk order.
  ///
  /// The snapshot is flat with child refs, so depth is reconstructed here: a
  /// root is a node no other node names as a child. Nodes unreachable from any
  /// root (a cycle, or a filtered-out parent) keep their original position
  /// rather than disappearing.
  List<ReleaseUiNode> _withinDepth(List<ReleaseUiNode> nodes, int maxDepth) {
    final byRef = <String, ReleaseUiNode>{
      for (final node in nodes)
        if (node.ref.isNotEmpty) node.ref: node,
    };
    final childRefs = <String>{
      for (final node in nodes)
        for (final child in node.children)
          if (byRef.containsKey(child)) child,
    };
    final roots = nodes
        .where((node) => !childRefs.contains(node.ref))
        .toList(growable: false);

    final ordered = <ReleaseUiNode>[];
    final seen = <String>{};

    void visit(ReleaseUiNode node, int depth) {
      if (node.ref.isNotEmpty && !seen.add(node.ref)) {
        return;
      }
      ordered.add(node);
      if (depth >= maxDepth) {
        return;
      }
      for (final child in node.children) {
        final next = byRef[child];
        if (next != null) {
          visit(next, depth + 1);
        }
      }
    }

    for (final root in roots) {
      visit(root, 0);
    }

    // Every node is reachable from a root unless the snapshot is pathological
    // (a pure child cycle, or all refs empty). Keep the answer non-empty rather
    // than silently returning nothing.
    if (ordered.isEmpty) {
      return nodes;
    }

    return List<ReleaseUiNode>.unmodifiable(ordered);
  }

  String _nextRequestId() => 'req_${++_requestCounter}';

  ReleaseToolCallResult _failure(
    String requestId,
    String code,
    String hint, {
    String? snapshotId,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final message = descriptorForReleaseErrorCode(code).message;
    return ReleaseToolCallResult(
      requestId: requestId,
      success: false,
      snapshotId: snapshotId,
      error: ReleaseToolError(code, '$message $hint', details: details),
    );
  }
}

/// Result of reading an optional bounded integer argument.
final class _BoundedInt {
  const _BoundedInt(this.value, [this.error]);

  final int? value;
  final String? error;
}

_BoundedInt _readBoundedInt(
  Map<String, Object?> arguments,
  String key, {
  required int fallback,
  required int ceiling,
}) {
  final raw = arguments[key];
  if (raw == null) {
    return _BoundedInt(fallback);
  }
  if (raw is! num || raw.toInt() != raw) {
    return _BoundedInt(null, '$key must be an integer.');
  }
  final value = raw.toInt();
  if (value < 0 || value > ceiling) {
    return _BoundedInt(null, '$key must be between 0 and $ceiling.');
  }
  return _BoundedInt(value);
}

String? _readString(Map<String, Object?> arguments, String key) {
  final raw = arguments[key];
  if (raw is! String) {
    return null;
  }
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}
