// packages/release_runtime/lib/src/ui/release_ui_types.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

/// Axis-aligned rectangle in logical pixels, in global coordinates.
@immutable
final class ReleaseUiRect {
  const ReleaseUiRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Reads `{left, top, right, bottom}`, tolerating ints and missing keys.
  factory ReleaseUiRect.fromJson(Object? json) {
    if (json is! Map) {
      return const ReleaseUiRect(left: 0, top: 0, right: 0, bottom: 0);
    }
    double read(String key) {
      final value = json[key];
      if (value is num) {
        return value.toDouble();
      }
      return 0;
    }

    return ReleaseUiRect(
      left: read('left'),
      top: read('top'),
      right: read('right'),
      bottom: read('bottom'),
    );
  }

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  bool get isEmpty => width <= 0 || height <= 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  @override
  String toString() => 'ReleaseUiRect($left, $top, $right, $bottom)';
}

/// One node of a UI snapshot.
///
/// The field vocabulary is the one the debug toolkit's semantic snapshot
/// already emits (`ref`, `type`, `identifier`, `label`, `value`, `hint`,
/// actions, children, viewport visibility), so the release runtime speaks the
/// same language as the `fmt_*` tools instead of inventing a second one.
///
/// [sensitive] is the release-only addition: the Flutter adapter sets it for
/// obscured/password semantics, and [ReleasePrivacyFilter] masks those nodes
/// before they leave the app.
@immutable
final class ReleaseUiNode {
  const ReleaseUiNode({
    required this.ref,
    required this.id,
    required this.type,
    required this.bounds,
    this.identifier,
    this.label,
    this.value,
    this.hint,
    this.actions = const <String>[],
    this.children = const <String>[],
    this.enabled,
    this.focused,
    this.checked,
    this.toggled,
    this.selected,
    this.visibleInViewport = false,
    this.centerInViewport = false,
    this.sensitive = false,
  });

  /// Reads one node from the map the snapshot builder emits.
  factory ReleaseUiNode.fromJson(Map<String, Object?> json) {
    List<String> readList(String key) {
      final value = json[key];
      if (value is! List) {
        return const <String>[];
      }
      return <String>[
        for (final entry in value)
          if (entry is String) entry,
      ];
    }

    bool? readBool(String key) {
      final value = json[key];
      return value is bool ? value : null;
    }

    return ReleaseUiNode(
      ref: json['ref'] as String? ?? '',
      id: json['id'] as int? ?? -1,
      type: json['type'] as String? ?? 'unknown',
      bounds: ReleaseUiRect.fromJson(json['bounds']),
      identifier: json['identifier'] as String?,
      label: json['label'] as String?,
      value: json['value'] as String?,
      hint: json['hint'] as String?,
      actions: readList('actions'),
      children: readList('children'),
      enabled: readBool('enabled'),
      focused: readBool('focused'),
      checked: readBool('checked'),
      toggled: readBool('toggled'),
      selected: readBool('selected'),
      visibleInViewport: readBool('visibleInViewport') ?? false,
      centerInViewport: readBool('centerInViewport') ?? false,
      sensitive: readBool('sensitive') ?? false,
    );
  }

  /// Stable identifier of this node within its snapshot.
  final String ref;

  /// Flutter `SemanticsNode.id`.
  final int id;

  /// Coarse role, for example `button`, `textField`, `label`.
  final String type;

  /// Node geometry in global logical pixels.
  final ReleaseUiRect bounds;

  /// `SemanticsData.identifier`, the app-authored stable name.
  final String? identifier;

  /// `SemanticsData.label`.
  final String? label;

  /// `SemanticsData.value` (a text field's contents).
  final String? value;

  /// `SemanticsData.hint`.
  final String? hint;

  /// Semantic actions the node exposes, for example `tap`, `setText`.
  final List<String> actions;

  /// Refs of child nodes that are in this snapshot.
  final List<String> children;

  final bool? enabled;
  final bool? focused;
  final bool? checked;
  final bool? toggled;
  final bool? selected;

  /// Whether the node's bounds overlap the viewport.
  final bool visibleInViewport;

  /// Whether the node's center is inside the viewport.
  final bool centerInViewport;

  /// Whether this node holds data that must never leave the device.
  final bool sensitive;

  bool get isInteractive => actions.isNotEmpty;

  /// Returns a copy with the redacted text fields replaced.
  ReleaseUiNode redacted({
    String? label,
    String? value,
    String? hint,
    bool? sensitive,
  }) => ReleaseUiNode(
    ref: ref,
    id: id,
    type: type,
    bounds: bounds,
    identifier: identifier,
    label: label ?? this.label,
    value: value ?? this.value,
    hint: hint ?? this.hint,
    actions: actions,
    children: children,
    enabled: enabled,
    focused: focused,
    checked: checked,
    toggled: toggled,
    selected: selected,
    visibleInViewport: visibleInViewport,
    centerInViewport: centerInViewport,
    sensitive: sensitive ?? this.sensitive,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'ref': ref,
    'id': id,
    'type': type,
    if (identifier != null) 'identifier': identifier,
    if (label != null) 'label': label,
    if (value != null) 'value': value,
    if (hint != null) 'hint': hint,
    if (actions.isNotEmpty) 'actions': actions,
    if (children.isNotEmpty) 'children': children,
    if (enabled != null) 'enabled': enabled,
    if (focused != null) 'focused': focused,
    if (checked != null) 'checked': checked,
    if (toggled != null) 'toggled': toggled,
    if (selected != null) 'selected': selected,
    'visibleInViewport': visibleInViewport,
    'centerInViewport': centerInViewport,
    if (sensitive) 'sensitive': true,
    'bounds': bounds.toJson(),
  };

  @override
  String toString() => 'ReleaseUiNode($ref, $type)';
}

/// One captured UI tree.
@immutable
final class ReleaseUiSnapshot {
  ReleaseUiSnapshot({
    required this.snapshotId,
    required List<ReleaseUiNode> nodes,
    required this.capturedAt,
    this.truncated = false,
    this.interactionSurface,
    this.routeName,
  }) : nodes = List<ReleaseUiNode>.unmodifiable(nodes);

  /// Id callers echo back when they act on a ref from this snapshot.
  final String snapshotId;

  /// Nodes in walk order.
  final List<ReleaseUiNode> nodes;

  /// UTC capture time.
  final DateTime capturedAt;

  /// Whether [nodes] was cut short by a budget.
  final bool truncated;

  /// `empty` / `sparse` / `rich` / `game_canvas`, from the snapshot builder.
  final String? interactionSurface;

  /// Route the app reported at capture time, when a route provider is wired.
  final String? routeName;

  int get nodeCount => nodes.length;

  ReleaseUiSnapshot copyWith({List<ReleaseUiNode>? nodes, bool? truncated}) =>
      ReleaseUiSnapshot(
        snapshotId: snapshotId,
        nodes: nodes ?? this.nodes,
        capturedAt: capturedAt,
        truncated: truncated ?? this.truncated,
        interactionSurface: interactionSurface,
        routeName: routeName,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'snapshotId': snapshotId,
    'capturedAt': capturedAt.toIso8601String(),
    'nodeCount': nodeCount,
    'truncated': truncated,
    if (interactionSurface != null) 'interactionSurface': interactionSurface,
    if (routeName != null) 'routeName': routeName,
    'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
  };

  @override
  String toString() =>
      'ReleaseUiSnapshot($snapshotId, nodes: $nodeCount, '
      'truncated: $truncated)';
}

/// What the app is showing right now.
@immutable
final class ReleasePageInfo {
  const ReleasePageInfo({
    required this.snapshotId,
    required this.capturedAt,
    this.routeName,
    this.interactionSurface,
    this.nodeCount = 0,
  });

  final String snapshotId;
  final DateTime capturedAt;
  final String? routeName;
  final String? interactionSurface;
  final int nodeCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'snapshotId': snapshotId,
    'capturedAt': capturedAt.toIso8601String(),
    if (routeName != null) 'routeName': routeName,
    if (interactionSurface != null) 'interactionSurface': interactionSurface,
    'nodeCount': nodeCount,
  };
}

/// The UI side of the release runtime.
///
/// The HTTP layer, permissions, and tools are platform-neutral; this interface
/// is the one seam that needs Flutter. The Flutter adapter
/// (`flutter_mcp_toolkit_release_flutter`) implements it on the UI isolate,
/// where `SemanticsNode` and `RenderView` are legal to touch.
///
/// Implementations must be safe to call from the runtime's own isolate, must
/// not retain `SemanticsNode` objects beyond a capture, and must never throw
/// for an ordinary "no tree yet" condition — return an empty snapshot instead.
abstract interface class ReleaseUiSnapshotSource {
  /// Captures the current tree.
  ///
  /// [maxNodes] and [identifierPrefix] are hints the source may apply before
  /// the runtime's own budgets, so a large tree is not materialized just to be
  /// thrown away.
  Future<ReleaseUiSnapshot> captureSnapshot({
    int? maxNodes,
    String? identifierPrefix,
  });

  /// Reports the current page without capturing a full tree when possible.
  Future<ReleasePageInfo> readCurrentPage();
}
