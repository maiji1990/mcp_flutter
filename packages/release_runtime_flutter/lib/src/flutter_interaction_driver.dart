// packages/release_runtime_flutter/lib/src/flutter_interaction_driver.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart'
    show GestureInteractionService, SemanticSnapshotService;

/// [ReleaseUiInteractionDriver] backed by the toolkit's gesture service.
///
/// Reuse again: `tapAtRef`, `enterTextAtRef`, and `scroll` already know how to
/// prefer a semantic action over synthesised pointer events, how to refuse a
/// ref whose node left the tree, and how to report what actually happened. This
/// driver only translates their result maps into the runtime's own result type
/// — it does not re-implement gesture dispatch.
///
/// What stays in the runtime, not here: whether the caller may act at all
/// (permission), whether the ref belongs to the snapshot it claims (store), and
/// whether the node exposes the action (catalog metadata). The gesture service
/// re-checks liveness anyway, so a stale ref is refused twice.
final class FlutterReleaseUiInteractionDriver
    implements ReleaseUiInteractionDriver {
  const FlutterReleaseUiInteractionDriver({this.routeProvider});

  /// Supplies the route the driver reports, so an interaction can prove the app
  /// is still on the page the snapshot was taken from.
  final ReleaseRouteProvider? routeProvider;

  @override
  Future<bool> isSnapshotCurrent(String snapshotId) async =>
      '${SemanticSnapshotService.currentSnapshotId}' == snapshotId;

  @override
  Future<String?> currentRouteName() async {
    final provider = routeProvider;
    if (provider == null) {
      return null;
    }
    try {
      return await provider.currentRouteName();
    } on Object {
      // A router that throws must not make an unknown route look known.
      return null;
    }
  }

  @override
  Future<ReleaseUiNodeState> inspect(String ref) async {
    final node = SemanticSnapshotService.resolveRef(ref);
    if (node == null || !node.attached) {
      return ReleaseUiNodeState.detached;
    }

    final SemanticsData data;
    try {
      data = node.getSemanticsData();
    } on Object {
      // A node that cannot even report its semantics is not actionable.
      return ReleaseUiNodeState.detached;
    }

    if (data.flagsCollection.isEnabled == Tristate.isFalse) {
      return ReleaseUiNodeState.disabled;
    }

    final visibility = SemanticSnapshotService.liveVisibilityForRef(ref);
    if (visibility['centerInViewport'] != true) {
      return ReleaseUiNodeState.hidden;
    }

    return ReleaseUiNodeState.attached;
  }

  @override
  Future<ReleaseDriverResult> tap(String ref) async =>
      _translate(await GestureInteractionService.tapAtRef(ref));

  @override
  Future<ReleaseDriverResult> setText(String ref, String text) async =>
      _translate(await GestureInteractionService.enterTextAtRef(ref, text));

  @override
  Future<ReleaseDriverResult> scroll(
    String ref,
    ReleaseScrollDirection direction, {
    double amount = 300,
  }) async => _translate(
    await GestureInteractionService.scroll(
      direction: direction.wireName,
      ref: ref,
      distance: amount,
    ),
  );

  /// Keeps the outcome, drops the prose.
  ///
  /// The gesture service's `hint` strings can quote node text, so only the
  /// stable `error` token crosses back into the runtime.
  static ReleaseDriverResult _translate(Map<String, Object?> result) {
    if (result['success'] == true) {
      return ReleaseDriverResult.success(
        details: <String, Object?>{
          if (result['via'] is String) 'via': result['via'],
          if (result['verified'] is bool) 'verified': result['verified'],
        },
      );
    }
    final error = result['error'];
    return ReleaseDriverResult.failure(
      error is String ? error : 'interaction_failed',
    );
  }
}
