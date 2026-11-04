// packages/release_runtime/lib/src/web/web_tools.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0).
//
// The `web_*` tool family. One rule shapes every tool here: no tool takes a
// JavaScript string. A client can list registered views, read a bounded DOM
// snapshot, and act through snapshot-scoped refs; it cannot run code, read
// cookies, or ask for the raw HTML.

import '../errors/release_mcp_error.dart';
import '../security/call_authorization.dart';
import '../security/permissions.dart';
import '../tools/release_tools.dart';
import 'release_web_privacy.dart';
import 'release_web_source.dart';
import 'release_web_types.dart';

/// The WebView tools: `web_list_views`, `web_get_tree`, `web_find_element`,
/// `web_get_state`, and the interaction trio.
///
/// Permission model: reads need `web:read`, actions need `web:interact`.
/// Neither is implied by `ui:read`/`ui:interact` — a page's DOM and a Flutter
/// widget tree are different capabilities.
final class ReleaseWebTools implements ReleaseToolSurface {
  ReleaseWebTools({
    required this.source,
    this.policy = const ReleaseWebPrivacyPolicy(),
    this.maxNodesCeiling = 500,
    this.maxDepthCeiling = 64,
    this.maxTextLength = 4096,
    this.maxScrollAmount = 5000,
  });

  /// Registered views and their DOM engines.
  final ReleaseEmbeddedWebSource source;

  /// Dart-side privacy rules, applied after the adapter's own redaction.
  final ReleaseWebPrivacyPolicy policy;

  final int maxNodesCeiling;
  final int maxDepthCeiling;
  final int maxTextLength;
  final double maxScrollAmount;

  final _WebSnapshotStore _store = _WebSnapshotStore();
  int _requests = 0;

  static final RegExp _viewIdPattern = RegExp(r'^[a-z][a-z0-9._-]{0,63}$');

  @override
  List<ReleaseToolDefinition> get tools => <ReleaseToolDefinition>[
    const ReleaseToolDefinition(
      name: 'web_list_views',
      description:
          'List the WebViews the app registered for agent access. Requires '
          'web:read.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.webRead,
    ),
    ReleaseToolDefinition(
      name: 'web_get_tree',
      description:
          'Read a bounded DOM snapshot of one registered WebView. Text of '
          'passwords, payment and personal fields is masked. Requires '
          'web:read.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'viewId': <String, Object?>{'type': 'string'},
          'maxNodes': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': maxNodesCeiling,
          },
          'maxDepth': <String, Object?>{
            'type': 'integer',
            'minimum': 0,
            'maximum': maxDepthCeiling,
          },
        },
        'required': <String>['viewId'],
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.webRead,
    ),
    ReleaseToolDefinition(
      name: 'web_find_element',
      description:
          'Find DOM elements by role, tag, text, or ref in a fresh snapshot. '
          'Returns up to five matches. Requires web:read.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'viewId': <String, Object?>{'type': 'string'},
          'role': <String, Object?>{'type': 'string'},
          'tag': <String, Object?>{'type': 'string'},
          'text': <String, Object?>{'type': 'string'},
        },
        'required': <String>['viewId'],
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.webRead,
    ),
    const ReleaseToolDefinition(
      name: 'web_click',
      description:
          'Click one element from a fresh DOM snapshot. Requires '
          'web:interact and the snapshotId that issued the ref.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'viewId': <String, Object?>{'type': 'string'},
          'ref': <String, Object?>{'type': 'string'},
          'snapshotId': <String, Object?>{'type': 'string'},
        },
        'required': <String>['viewId', 'ref', 'snapshotId'],
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.webInteract,
    ),
    ReleaseToolDefinition(
      name: 'web_set_text',
      description:
          'Replace the text of a DOM control from a fresh snapshot. Refuses '
          'password and sensitive fields. Requires web:interact.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'viewId': <String, Object?>{'type': 'string'},
          'ref': <String, Object?>{'type': 'string'},
          'snapshotId': <String, Object?>{'type': 'string'},
          'text': <String, Object?>{'type': 'string'},
        },
        'required': <String>['viewId', 'ref', 'snapshotId', 'text'],
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.webInteract,
    ),
    const ReleaseToolDefinition(
      name: 'web_scroll',
      description:
          'Scroll the page or a scroll container from a fresh snapshot. '
          'Requires web:interact.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'viewId': <String, Object?>{'type': 'string'},
          'ref': <String, Object?>{'type': 'string'},
          'snapshotId': <String, Object?>{'type': 'string'},
          'direction': <String, Object?>{
            'type': 'string',
            'enum': <String>['up', 'down', 'left', 'right'],
          },
          'amount': <String, Object?>{'type': 'number', 'minimum': 1},
        },
        'required': <String>['viewId', 'direction', 'snapshotId'],
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.webInteract,
    ),
    const ReleaseToolDefinition(
      name: 'web_get_state',
      description:
          'Report the URL (origin and path only) and loading state of one '
          'registered WebView. Requires web:read.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'viewId': <String, Object?>{'type': 'string'},
        },
        'required': <String>['viewId'],
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.webRead,
    ),
  ];

  @override
  Future<ReleaseToolCallResult> call(
    String name,
    Map<String, Object?> arguments, {
    ReleaseCallAuthorization? authorization,
  }) {
    final authority =
        authorization ?? const ReleaseCallAuthorization.unchecked();
    switch (name) {
      case 'web_list_views':
        return _listViews();
      case 'web_get_tree':
        return _getTree(arguments);
      case 'web_find_element':
        return _findElement(arguments);
      case 'web_get_state':
        return _getState(arguments);
      case 'web_click':
        return _click(arguments, authority);
      case 'web_set_text':
        return _setText(arguments, authority);
      case 'web_scroll':
        return _scroll(arguments, authority);
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

  Future<ReleaseToolCallResult> _listViews() async {
    final requestId = _nextRequestId();
    try {
      final views = await source.listViews();
      return ReleaseToolCallResult(
        requestId: requestId,
        success: true,
        data: <String, Object?>{
          'views': views.map((view) => view.toJson()).toList(growable: false),
        },
      );
    } catch (error) {
      return _unknown(requestId, error);
    }
  }

  Future<ReleaseToolCallResult> _getTree(Map<String, Object?> arguments) async {
    final requestId = _nextRequestId();
    final viewId = _readString(arguments, 'viewId');
    final invalidView = _checkViewId(requestId, viewId);
    if (invalidView != null) {
      return invalidView;
    }

    final maxNodes = _readBoundedInt(
      arguments,
      'maxNodes',
      fallback: 200,
      ceiling: maxNodesCeiling,
    );
    if (maxNodes.error != null) {
      return _failure(requestId, 'invalid_argument', maxNodes.error!);
    }
    final maxDepth = _readBoundedInt(
      arguments,
      'maxDepth',
      fallback: 32,
      ceiling: maxDepthCeiling,
    );
    if (maxDepth.error != null) {
      return _failure(requestId, 'invalid_argument', maxDepth.error!);
    }

    return _captureAndPublish(
      requestId,
      viewId!,
      maxNodes: maxNodes.value!,
      maxDepth: maxDepth.value!,
      withNodes: true,
    );
  }

  Future<ReleaseToolCallResult> _findElement(
    Map<String, Object?> arguments,
  ) async {
    final requestId = _nextRequestId();
    final viewId = _readString(arguments, 'viewId');
    final invalidView = _checkViewId(requestId, viewId);
    if (invalidView != null) {
      return invalidView;
    }
    final role = _readString(arguments, 'role');
    final tag = _readString(arguments, 'tag');
    final text = _readString(arguments, 'text');
    if (role == null && tag == null && text == null) {
      return _failure(
        requestId,
        'invalid_argument',
        'Pass at least one of role, tag, or text.',
      );
    }

    final capture = await _capture(
      requestId,
      viewId!,
      maxNodes: maxNodesCeiling,
      maxDepth: maxDepthCeiling,
    );
    if (capture.error != null) {
      return capture.error!;
    }
    final snapshot = capture.snapshot!;

    final matches = <ReleaseWebNode>[];
    for (final node in snapshot.nodes) {
      if (role != null && node.role.toLowerCase() != role.toLowerCase()) {
        continue;
      }
      if (tag != null && node.tag.toLowerCase() != tag.toLowerCase()) {
        continue;
      }
      if (text != null &&
          !(node.text ?? '').toLowerCase().contains(text.toLowerCase()) &&
          !(node.label ?? '').toLowerCase().contains(text.toLowerCase())) {
        continue;
      }
      matches.add(node);
      if (matches.length == 5) {
        break;
      }
    }

    if (matches.isEmpty) {
      return _failure(
        requestId,
        ReleaseMcpErrorCode.elementNotFound,
        'No DOM element matches the query.',
        snapshotId: snapshot.snapshotId,
        details: <String, Object?>{'nodeCount': snapshot.nodeCount},
      );
    }

    return ReleaseToolCallResult(
      requestId: requestId,
      success: true,
      snapshotId: snapshot.snapshotId,
      data: <String, Object?>{
        'viewId': snapshot.viewId,
        'url': snapshot.url,
        'matchCount': matches.length,
        'matches': matches.map((node) => node.toJson()).toList(growable: false),
      },
    );
  }

  Future<ReleaseToolCallResult> _getState(
    Map<String, Object?> arguments,
  ) async {
    final requestId = _nextRequestId();
    final viewId = _readString(arguments, 'viewId');
    final invalidView = _checkViewId(requestId, viewId);
    if (invalidView != null) {
      return invalidView;
    }
    try {
      final state = await source.readState(viewId: viewId!);
      return ReleaseToolCallResult(
        requestId: requestId,
        success: true,
        data: state.toJson(),
      );
    } on Object catch (error) {
      return _mapSourceError(requestId, error);
    }
  }

  Future<ReleaseToolCallResult> _click(
    Map<String, Object?> arguments,
    ReleaseCallAuthorization authorization,
  ) => _act(
    arguments: arguments,
    authorization: authorization,
    permission: ReleasePermissionId.webInteract,
    action: 'click',
    extra: const <String, Object?>{},
  );

  Future<ReleaseToolCallResult> _setText(
    Map<String, Object?> arguments,
    ReleaseCallAuthorization authorization,
  ) {
    final text = arguments['text'];
    if (text is! String || text.length > maxTextLength) {
      return Future<ReleaseToolCallResult>.value(
        _failure(
          _nextRequestId(),
          ReleaseMcpErrorCode.invalidArgument,
          'text must be a string of at most $maxTextLength characters.',
        ),
      );
    }
    return _act(
      arguments: arguments,
      authorization: authorization,
      permission: ReleasePermissionId.webInteract,
      action: 'setText',
      extra: <String, Object?>{'text': text},
    );
  }

  Future<ReleaseToolCallResult> _scroll(
    Map<String, Object?> arguments,
    ReleaseCallAuthorization authorization,
  ) {
    final direction = _readString(arguments, 'direction');
    if (direction == null ||
        !const <String>{'up', 'down', 'left', 'right'}.contains(direction)) {
      return Future<ReleaseToolCallResult>.value(
        _failure(
          _nextRequestId(),
          ReleaseMcpErrorCode.invalidArgument,
          'direction must be one of up, down, left, right.',
        ),
      );
    }
    final rawAmount = arguments['amount'];
    final amount = rawAmount == null
        ? 300.0
        : (rawAmount is num ? rawAmount.toDouble() : null);
    if (amount == null || amount <= 0 || amount > maxScrollAmount) {
      return Future<ReleaseToolCallResult>.value(
        _failure(
          _nextRequestId(),
          ReleaseMcpErrorCode.invalidArgument,
          'amount must be a number between 1 and $maxScrollAmount.',
        ),
      );
    }
    return _act(
      arguments: arguments,
      authorization: authorization,
      permission: ReleasePermissionId.webInteract,
      action: 'scroll',
      extra: <String, Object?>{'direction': direction, 'amount': amount},
    );
  }

  /// Shared validation and dispatch for the three interaction tools.
  Future<ReleaseToolCallResult> _act({
    required Map<String, Object?> arguments,
    required ReleaseCallAuthorization authorization,
    required ReleasePermissionId permission,
    required String action,
    required Map<String, Object?> extra,
  }) async {
    final requestId = _nextRequestId();
    final viewId = _readString(arguments, 'viewId');
    final invalidView = _checkViewId(requestId, viewId);
    if (invalidView != null) {
      return invalidView;
    }
    final ref = _readString(arguments, 'ref');
    if (ref == null) {
      return _failure(requestId, 'invalid_argument', 'ref is required.');
    }
    final snapshotId = _readString(arguments, 'snapshotId');
    if (snapshotId == null) {
      return _failure(
        requestId,
        ReleaseMcpErrorCode.snapshotRequired,
        'Pass the snapshotId that issued the ref.',
      );
    }

    if (!_store.isUsable(viewId!, snapshotId)) {
      return _failure(
        requestId,
        ReleaseMcpErrorCode.staleSnapshot,
        'Take a fresh web_get_tree and use refs from it.',
        snapshotId: snapshotId,
        details: <String, Object?>{
          'reason': _store.contains(viewId, snapshotId)
              ? 'superseded_or_consumed'
              : 'unknown_snapshot',
        },
      );
    }

    final node = _store.node(viewId, snapshotId, ref);
    if (node == null) {
      return _failure(
        requestId,
        ReleaseMcpErrorCode.unknownRef,
        'No node with that ref in this snapshot.',
        snapshotId: snapshotId,
        details: <String, Object?>{'ref': ref},
      );
    }
    if (action == 'setText' &&
        (node.sensitive || node.inputType.toLowerCase() == 'password')) {
      return _failure(
        requestId,
        ReleaseMcpErrorCode.nodeSensitive,
        'Refusing to type into a sensitive field.',
        snapshotId: snapshotId,
        details: <String, Object?>{'ref': ref},
      );
    }

    // AUTH-01: the consent is re-read immediately before the action runs.
    if (!authorization.allows(permission)) {
      return _failure(
        requestId,
        ReleaseMcpErrorCode.permissionDenied,
        'Consent was withdrawn.',
        details: <String, Object?>{'permission': permission.wireName},
      );
    }

    final ReleaseWebActionResult outcome;
    try {
      outcome = switch (action) {
        'click' => await source.click(
          viewId: viewId,
          ref: ref,
          snapshotId: snapshotId,
        ),
        'setText' => await source.setText(
          viewId: viewId,
          ref: ref,
          snapshotId: snapshotId,
          text: extra['text']! as String,
        ),
        _ => await source.scroll(
          viewId: viewId,
          ref: ref,
          snapshotId: snapshotId,
          direction: extra['direction']! as String,
          amount: extra['amount']! as double,
        ),
      };
    } on Object catch (error) {
      return _mapSourceError(requestId, error);
    }

    if (!outcome.ok) {
      return _failure(
        requestId,
        _codeForToken(outcome.error),
        'The page refused the action.',
        snapshotId: snapshotId,
        details: <String, Object?>{
          'ref': ref,
          'reason': outcome.error ?? 'interaction_failed',
        },
      );
    }

    _store.consume(viewId);
    return ReleaseToolCallResult(
      requestId: requestId,
      success: true,
      snapshotId: snapshotId,
      data: <String, Object?>{
        'viewId': viewId,
        'dispatched': true,
        'ref': ref,
        'action': action,
        ...outcome.details,
      },
    );
  }

  Future<ReleaseToolCallResult> _captureAndPublish(
    String requestId,
    String viewId, {
    required int maxNodes,
    required int maxDepth,
    required bool withNodes,
  }) async {
    final capture = await _capture(
      requestId,
      viewId,
      maxNodes: maxNodes,
      maxDepth: maxDepth,
    );
    if (capture.error != null) {
      return capture.error!;
    }
    final snapshot = capture.snapshot!;
    return ReleaseToolCallResult(
      requestId: requestId,
      success: true,
      snapshotId: snapshot.snapshotId,
      data: <String, Object?>{
        'viewId': snapshot.viewId,
        'capturedAt': snapshot.capturedAt.toIso8601String(),
        'url': snapshot.url,
        'navigationEpoch': snapshot.navigationEpoch,
        'nodeCount': snapshot.nodeCount,
        'truncated': snapshot.truncated,
        if (withNodes)
          'nodes': snapshot.nodes
              .map((node) => node.toJson())
              .toList(growable: false),
      },
    );
  }

  /// Captures, screens, and publishes a snapshot; returns either the more
  /// specific refusal or the snapshot.
  Future<({ReleaseToolCallResult? error, ReleaseWebDomSnapshot? snapshot})>
  _capture(
    String requestId,
    String viewId, {
    required int maxNodes,
    required int maxDepth,
  }) async {
    final ReleaseWebCaptureResult result;
    try {
      result = await source.capture(
        viewId: viewId,
        maxNodes: maxNodes,
        maxDepth: maxDepth,
      );
    } on Object catch (error) {
      return (error: _mapSourceError(requestId, error), snapshot: null);
    }
    if (!result.ok) {
      return (
        error: _failure(
          requestId,
          _codeForToken(result.error),
          'The page could not be read.',
          details: <String, Object?>{
            'reason': result.error ?? 'capture_failed',
          },
        ),
        snapshot: null,
      );
    }

    final screening = policy.screen(result.snapshot!);
    if (screening.isDenied) {
      return (
        error: _failure(
          requestId,
          ReleaseMcpErrorCode.routeDenied,
          'The app privacy policy refuses to read this page.',
          details: <String, Object?>{'reason': screening.denialReason},
        ),
        snapshot: null,
      );
    }

    final snapshot = screening.snapshot!;
    _store.publish(snapshot);
    return (error: null, snapshot: snapshot);
  }

  ReleaseToolCallResult? _checkViewId(String requestId, String? viewId) {
    if (viewId == null || !_viewIdPattern.hasMatch(viewId)) {
      return _failure(
        requestId,
        ReleaseMcpErrorCode.viewNotFound,
        'Pass the viewId from web_list_views.',
      );
    }
    return null;
  }

  ReleaseToolCallResult _mapSourceError(String requestId, Object error) {
    if (error is ReleaseMcpException) {
      return _failure(
        requestId,
        error.code,
        'The WebView adapter refused the request.',
        details: error.details,
      );
    }
    return _failure(
      requestId,
      ReleaseMcpErrorCode.unknown,
      'The WebView adapter failed.',
      details: <String, Object?>{'cause': error.runtimeType.toString()},
    );
  }

  static String _codeForToken(String? token) => switch (token) {
    'origin_denied' || 'insecure_origin' => ReleaseMcpErrorCode.originDenied,
    'view_not_found' => ReleaseMcpErrorCode.viewNotFound,
    'path_denied' => ReleaseMcpErrorCode.routeDenied,
    'stale_ref' ||
    'navigation_changed' ||
    'snapshot_expired' => ReleaseMcpErrorCode.staleSnapshot,
    'target_sensitive' => ReleaseMcpErrorCode.nodeSensitive,
    'target_disabled' ||
    'target_hidden' ||
    'not_actionable' => ReleaseMcpErrorCode.nodeNotActionable,
    'not_editable' ||
    'unsupported_action' => ReleaseMcpErrorCode.unsupportedAction,
    'not_found' => ReleaseMcpErrorCode.unknownRef,
    'timeout' || 'script_failed' => ReleaseMcpErrorCode.interactionFailed,
    _ => ReleaseMcpErrorCode.interactionFailed,
  };

  String _nextRequestId() => 'req_${++_requests}';

  ReleaseToolCallResult _unknown(String requestId, Object error) => _failure(
    requestId,
    ReleaseMcpErrorCode.unknown,
    'The WebView adapter failed.',
    details: <String, Object?>{'cause': error.runtimeType.toString()},
  );

  ReleaseToolCallResult _failure(
    String requestId,
    String code,
    String hint, {
    String? snapshotId,
    Map<String, Object?> details = const <String, Object?>{},
  }) => ReleaseToolCallResult(
    requestId: requestId,
    success: false,
    snapshotId: snapshotId,
    error: ReleaseToolError(
      code,
      '${descriptorForReleaseErrorCode(code).message} $hint',
      details: details,
    ),
  );
}

/// Keeps the latest, actionable snapshot per view.
///
/// Per-view because two WebViews can be mounted at once (a checkout flow with a
/// header cart); a read in one must not invalidate the other's refs.
final class _WebSnapshotStore {
  final Map<String, ReleaseWebDomSnapshot> _latest =
      <String, ReleaseWebDomSnapshot>{};
  final Set<String> _consumed = <String>{};

  void publish(ReleaseWebDomSnapshot snapshot) {
    _latest[snapshot.viewId] = snapshot;
    _consumed.remove(_key(snapshot.viewId, snapshot.snapshotId));
  }

  bool contains(String viewId, String snapshotId) =>
      _latest[viewId]?.snapshotId == snapshotId;

  bool isUsable(String viewId, String snapshotId) =>
      contains(viewId, snapshotId) &&
      !_consumed.contains(_key(viewId, snapshotId));

  ReleaseWebNode? node(String viewId, String snapshotId, String ref) {
    final snapshot = _latest[viewId];
    if (snapshot == null || snapshot.snapshotId != snapshotId) {
      return null;
    }
    for (final node in snapshot.nodes) {
      if (node.ref == ref) {
        return node;
      }
    }
    return null;
  }

  void consume(String viewId) {
    final snapshot = _latest[viewId];
    if (snapshot != null) {
      _consumed.add(_key(viewId, snapshot.snapshotId));
    }
  }

  String _key(String viewId, String snapshotId) => '$viewId|$snapshotId';
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
