// packages/release_runtime/test/support/fake_interaction_driver.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';

/// Driver that records calls and can be told how the UI answers.
final class FakeDriver implements ReleaseUiInteractionDriver {
  FakeDriver({
    this.snapshotId = 'ui-1',
    Map<String, ReleaseUiNodeState> states =
        const <String, ReleaseUiNodeState>{},
    this.failWith,
    this.throws = false,
  }) : states = Map<String, ReleaseUiNodeState>.of(states);

  String snapshotId;
  final Map<String, ReleaseUiNodeState> states;
  String? failWith;
  bool throws;

  final List<String> tapped = <String>[];
  final List<(String, String)> typed = <(String, String)>[];
  final List<(String, String, double)> scrolled = <(String, String, double)>[];

  @override
  Future<bool> isSnapshotCurrent(String id) async => id == snapshotId;

  @override
  Future<ReleaseUiNodeState> inspect(String ref) async =>
      states[ref] ?? ReleaseUiNodeState.attached;

  @override
  Future<ReleaseDriverResult> tap(String ref) async {
    if (throws) {
      throw StateError('driver blew up');
    }
    final failure = failWith;
    if (failure != null) {
      return ReleaseDriverResult.failure(failure);
    }
    tapped.add(ref);
    return const ReleaseDriverResult.success(
      details: <String, Object?>{'via': 'semantic_action'},
    );
  }

  @override
  Future<ReleaseDriverResult> setText(String ref, String text) async {
    final failure = failWith;
    if (failure != null) {
      return ReleaseDriverResult.failure(failure);
    }
    typed.add((ref, text));
    return const ReleaseDriverResult.success();
  }

  @override
  Future<ReleaseDriverResult> scroll(
    String ref,
    ReleaseScrollDirection direction, {
    double amount = 300,
  }) async {
    final failure = failWith;
    if (failure != null) {
      return ReleaseDriverResult.failure(failure);
    }
    scrolled.add((ref, direction.wireName, amount));
    return const ReleaseDriverResult.success();
  }
}
