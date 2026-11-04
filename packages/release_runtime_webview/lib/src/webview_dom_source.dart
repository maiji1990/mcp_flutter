// packages/release_runtime_webview/lib/src/webview_dom_source.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0).

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';

import 'dom_action_script.dart';
import 'dom_snapshot_script.dart';
import 'webview_registry.dart';

/// [ReleaseEmbeddedWebSource] over a [ReleaseWebViewRegistry].
///
/// One instance serves every registered view. The adapter owns three checks the
/// core cannot do: it reads the controller's current URL, it refuses pages
/// outside the registered origins, and it holds the navigation epoch that makes
/// a ref from the previous page unusable.
final class WebViewDomReleaseSource implements ReleaseEmbeddedWebSource {
  WebViewDomReleaseSource(
    this.registry, {
    this.maxScriptResultBytes = 1024 * 1024,
  });

  /// Views the app registered.
  final ReleaseWebViewRegistry registry;

  /// Largest JavaScript result accepted, as a rough memory guard.
  final int maxScriptResultBytes;

  static final Random _random = Random.secure();

  @override
  Future<List<ReleaseWebViewInfo>> listViews() async {
    final infos = <ReleaseWebViewInfo>[];
    for (final registration in registry.registrations) {
      String? url;
      try {
        url = await registration.engine.currentUrl().timeout(
          registration.timeout,
        );
      } on Object {
        url = null;
      }
      infos.add(
        ReleaseWebViewInfo(
          viewId: registration.viewId,
          allowedOrigins: registration.allowedOrigins,
          url: url,
        ),
      );
    }
    return infos;
  }

  @override
  Future<ReleaseWebCaptureResult> capture({
    required String viewId,
    int maxNodes = 200,
    int maxDepth = 32,
  }) async {
    final registration = registry.registrationFor(viewId);
    if (registration == null) {
      return const ReleaseWebCaptureResult.failure('view_not_found');
    }
    final url = await _currentUrl(registration);
    final origin = webOriginOf(url);
    if (origin == null || !registration.allowedOrigins.contains(origin)) {
      return const ReleaseWebCaptureResult.failure('origin_denied');
    }
    final nonce = _token();
    final result = await _execute(
      registration,
      buildDomSnapshotScript(
        allowedOrigins: registration.allowedOrigins,
        maxNodes: maxNodes,
        maxDepth: maxDepth,
        nonce: nonce,
      ),
    );
    if (result.error != null) {
      return ReleaseWebCaptureResult.failure(result.error!);
    }
    final data = result.data!;
    final token = data['error'];
    if (token is String) {
      return ReleaseWebCaptureResult.failure(token);
    }
    if (data['origin'] != origin) {
      return const ReleaseWebCaptureResult.failure('origin_denied');
    }
    final href = data['href'] is String ? data['href']! as String : url;
    if (webOriginOf(href) != origin) {
      return const ReleaseWebCaptureResult.failure('origin_denied');
    }
    // The script reports the document it actually read. A SPA History
    // navigation changes `location.href` without a reload, so the snapshot
    // belongs to the new epoch; an older snapshot id is refused by the action
    // path, and the next read sees the new page.
    final epoch = registration.navigation.observe(href);

    final nodes = <ReleaseWebNode>[];
    final rawNodes = data['nodes'];
    if (rawNodes is List) {
      for (final entry in rawNodes) {
        if (entry is! Map) {
          continue;
        }
        nodes.add(ReleaseWebNode.fromJson(entry.cast<String, Object?>()));
        if (nodes.length >= maxNodes) {
          break;
        }
      }
    }

    final snapshot = ReleaseWebDomSnapshot(
      viewId: viewId,
      snapshotId: 'web:$viewId:$epoch:$nonce',
      capturedAt: DateTime.now().toUtc(),
      nodes: nodes,
      url: sanitizeWebUrl(href),
      title: data['title'] is String ? data['title']! as String : null,
      origin: origin,
      navigationEpoch: epoch,
      truncated: data['truncated'] == true,
    );

    final screening = registration.privacyPolicy.screen(snapshot);
    if (screening.isDenied) {
      return ReleaseWebCaptureResult.failure(
        screening.denialReason ?? 'path_denied',
      );
    }
    return ReleaseWebCaptureResult.ok(screening.snapshot!);
  }

  @override
  Future<ReleaseWebActionResult> click({
    required String viewId,
    required String ref,
    required String snapshotId,
  }) => _act(kind: 'click', viewId: viewId, ref: ref, snapshotId: snapshotId);

  @override
  Future<ReleaseWebActionResult> setText({
    required String viewId,
    required String ref,
    required String snapshotId,
    required String text,
  }) => _act(
    kind: 'setText',
    viewId: viewId,
    ref: ref,
    snapshotId: snapshotId,
    text: text,
  );

  @override
  Future<ReleaseWebActionResult> scroll({
    required String viewId,
    required String ref,
    required String snapshotId,
    required String direction,
    double amount = 300,
  }) => _act(
    kind: 'scroll',
    viewId: viewId,
    ref: ref,
    snapshotId: snapshotId,
    direction: direction,
    amount: amount,
  );

  @override
  Future<ReleaseWebViewState> readState({required String viewId}) async {
    final registration = registry.registrationFor(viewId);
    if (registration == null) {
      throw ReleaseMcpException(ReleaseMcpErrorCode.viewNotFound);
    }
    final url = await _currentUrl(registration);
    final origin = webOriginOf(url);
    if (origin == null || !registration.allowedOrigins.contains(origin)) {
      throw ReleaseMcpException(ReleaseMcpErrorCode.originDenied);
    }
    final epoch = registration.navigation.observe(url);
    return ReleaseWebViewState(
      viewId: viewId,
      url: url ?? '',
      origin: origin,
      navigationEpoch: epoch,
    );
  }

  Future<ReleaseWebActionResult> _act({
    required String kind,
    required String viewId,
    required String ref,
    required String snapshotId,
    String? text,
    String? direction,
    double? amount,
  }) async {
    final registration = registry.registrationFor(viewId);
    if (registration == null) {
      return const ReleaseWebActionResult.failure('view_not_found');
    }
    final parsed = _parseSnapshotId(snapshotId, viewId);
    if (parsed == null) {
      return const ReleaseWebActionResult.failure('stale_ref');
    }
    final url = await _currentUrl(registration);
    final origin = webOriginOf(url);
    if (origin == null || !registration.allowedOrigins.contains(origin)) {
      return const ReleaseWebActionResult.failure('origin_denied');
    }
    // Do not advance the epoch from `currentUrl` here: WebView's reported URL
    // can lag a SPA History change. The page script owns the precise check
    // (`store.href` vs `location.href`); this only rejects a snapshot issued
    // in an older epoch.
    if (registration.navigation.value != parsed.$1) {
      return const ReleaseWebActionResult.failure('navigation_changed');
    }

    final script = switch (kind) {
      'click' => buildDomClickScript(
        allowedOrigins: registration.allowedOrigins,
        ref: ref,
        nonce: parsed.$2,
      ),
      'setText' => buildDomSetTextScript(
        allowedOrigins: registration.allowedOrigins,
        ref: ref,
        nonce: parsed.$2,
        text: text ?? '',
      ),
      _ => buildDomScrollScript(
        allowedOrigins: registration.allowedOrigins,
        ref: ref,
        nonce: parsed.$2,
        direction: direction ?? 'down',
        amount: amount ?? 300,
      ),
    };

    final result = await _execute(registration, script);
    if (result.error != null) {
      return ReleaseWebActionResult.failure(result.error!);
    }
    final data = result.data!;
    final token = data['error'];
    if (token is String) {
      return ReleaseWebActionResult.failure(
        token,
        details: <String, Object?>{'reason': data['reason']},
      );
    }
    final href = data['href'] is String ? data['href']! as String : url;
    if (webOriginOf(href) != origin) {
      return const ReleaseWebActionResult.failure('origin_denied');
    }
    final navigated = href != url;
    if (navigated) {
      registration.navigation.observe(href);
    }
    return ReleaseWebActionResult.success(
      details: <String, Object?>{
        'url': sanitizeWebUrl(href),
        'navigated': navigated,
      },
    );
  }

  /// `web:<viewId>:<epoch>:<nonce>`, or null when it is malformed.
  (int, String)? _parseSnapshotId(String snapshotId, String viewId) {
    final parts = snapshotId.split(':');
    if (parts.length != 4 || parts[0] != 'web' || parts[1] != viewId) {
      return null;
    }
    final epoch = int.tryParse(parts[2]);
    if (epoch == null || parts[3].isEmpty) {
      return null;
    }
    return (epoch, parts[3]);
  }

  Future<String?> _currentUrl(ReleaseWebViewRegistration registration) async {
    try {
      return await registration.engine.currentUrl().timeout(
        registration.timeout,
      );
    } on Object {
      return null;
    }
  }

  Future<({Map<String, Object?>? data, String? error})> _execute(
    ReleaseWebViewRegistration registration,
    String script,
  ) async {
    final Object? raw;
    try {
      raw = await registration.engine
          .runJavaScript(script)
          .timeout(registration.timeout);
    } on TimeoutException {
      return (data: null, error: 'timeout');
    } on Object {
      return (data: null, error: 'script_failed');
    }
    if (raw is String && raw.length > maxScriptResultBytes) {
      return (data: null, error: 'script_failed');
    }
    final decoded = _decode(raw);
    if (decoded is! Map) {
      return (data: null, error: 'script_failed');
    }
    return (data: decoded.cast<String, Object?>(), error: null);
  }

  /// Accepts every shape `webview_flutter` can return.
  ///
  /// Android hands back `evaluateJavascript`'s raw JSON text, so a script that
  /// returns `JSON.stringify(...)` arrives **double encoded**
  /// (`"{\"origin\":...}"`); iOS returns the decoded value. Unwrap strings
  /// until a non-string appears, bounded so a pathological result cannot loop.
  Object? _decode(Object? raw) {
    var value = raw;
    for (var depth = 0; depth < 3; depth += 1) {
      if (value is! String) {
        break;
      }
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      try {
        value = jsonDecode(trimmed);
      } on Object {
        return null;
      }
    }
    return value is Map ? value : null;
  }

  static String _token() {
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i += 1) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
