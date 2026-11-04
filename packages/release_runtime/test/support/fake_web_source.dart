// packages/release_runtime/test/support/fake_web_source.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';

/// In-memory [ReleaseEmbeddedWebSource] for the `web_*` tool tests.
final class FakeWebSource implements ReleaseEmbeddedWebSource {
  FakeWebSource({
    List<ReleaseWebViewInfo> views = const <ReleaseWebViewInfo>[],
    List<ReleaseWebNode> nodes = const <ReleaseWebNode>[],
    this.url = 'https://app.example.com/orders',
    this.captureError,
    this.actionResult,
  }) : views = List<ReleaseWebViewInfo>.of(views),
       nodes = List<ReleaseWebNode>.of(nodes);

  final List<ReleaseWebViewInfo> views;
  List<ReleaseWebNode> nodes;
  String url;
  String? captureError;
  ReleaseWebActionResult? actionResult;

  int captures = 0;
  int? lastMaxNodes;
  int? lastMaxDepth;
  final List<String> actions = <String>[];
  final List<String> refs = <String>[];
  String? lastText;

  int _snapshots = 0;

  @override
  Future<List<ReleaseWebViewInfo>> listViews() async => views;

  @override
  Future<ReleaseWebCaptureResult> capture({
    required String viewId,
    int maxNodes = 200,
    int maxDepth = 32,
  }) async {
    captures += 1;
    lastMaxNodes = maxNodes;
    lastMaxDepth = maxDepth;
    final error = captureError;
    if (error != null) {
      return ReleaseWebCaptureResult.failure(error);
    }
    _snapshots += 1;
    return ReleaseWebCaptureResult.ok(
      ReleaseWebDomSnapshot(
        viewId: viewId,
        snapshotId: 'web:$viewId:1:nonce$_snapshots',
        capturedAt: DateTime.utc(2026, 11, 4, 9),
        nodes: nodes.take(maxNodes).toList(growable: false),
        url: url,
        origin: webOriginOf(url),
        navigationEpoch: 1,
      ),
    );
  }

  @override
  Future<ReleaseWebActionResult> click({
    required String viewId,
    required String ref,
    required String snapshotId,
  }) async {
    actions.add('click');
    refs.add(ref);
    return actionResult ?? const ReleaseWebActionResult.success();
  }

  @override
  Future<ReleaseWebActionResult> setText({
    required String viewId,
    required String ref,
    required String snapshotId,
    required String text,
  }) async {
    actions.add('setText');
    refs.add(ref);
    lastText = text;
    return actionResult ?? const ReleaseWebActionResult.success();
  }

  @override
  Future<ReleaseWebActionResult> scroll({
    required String viewId,
    required String ref,
    required String snapshotId,
    required String direction,
    double amount = 300,
  }) async {
    actions.add('scroll');
    refs.add(ref);
    return actionResult ?? const ReleaseWebActionResult.success();
  }

  @override
  Future<ReleaseWebViewState> readState({required String viewId}) async =>
      ReleaseWebViewState(
        viewId: viewId,
        url: url,
        origin: webOriginOf(url),
        navigationEpoch: 1,
      );
}
