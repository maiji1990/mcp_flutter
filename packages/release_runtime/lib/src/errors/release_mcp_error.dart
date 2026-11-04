// packages/release_runtime/lib/src/errors/release_mcp_error.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

import '../config/release_mcp_config.dart';

/// Descriptor for one stable runtime error code.
@immutable
final class ReleaseErrorDescriptor {
  const ReleaseErrorDescriptor({
    required this.code,
    required this.category,
    required this.retryable,
    required this.httpLikeStatus,
    required this.message,
  });

  /// Stable wire code.
  final String code;

  /// Coarse grouping used by clients to decide how to react.
  final String category;

  /// Whether retrying the same call can succeed without user action.
  final bool retryable;

  /// HTTP status the MCP adapter should map this code onto.
  final int httpLikeStatus;

  /// Operator-facing default message. Never contains request data.
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'category': category,
    'retryable': retryable,
    'httpLikeStatus': httpLikeStatus,
    'message': message,
  };
}

/// Error categories exposed by the release runtime.
abstract final class ReleaseMcpErrorCategory {
  static const String config = 'config';
  static const String validation = 'validation';
  static const String permission = 'permission';
  static const String state = 'state';
  static const String transport = 'transport';
  static const String execution = 'execution';
  static const String capability = 'capability';
  static const String internal = 'internal';
}

/// Stable error-code catalog for the release runtime.
///
/// Codes are part of the fork's public contract: adding one is a minor change,
/// renaming one is breaking.
abstract final class ReleaseMcpErrorCode {
  /// The supplied [ReleaseMcpConfig] violates its own invariants.
  static const String invalidConfig = 'invalid_config';

  /// A permission string could not be parsed into [ReleasePermissionId].
  static const String invalidPermissionId = 'invalid_permission_id';

  /// A non-read-only session was requested without explicit authorization.
  static const String authorizationMissing = 'authorization_missing';

  /// The session does not hold the permission a call requires.
  static const String permissionDenied = 'permission_denied';

  /// Lifecycle transition rejected by the state machine.
  static const String invalidStateTransition = 'invalid_state_transition';

  /// No transport is attached, so there is nothing to serve MCP over.
  static const String transportNotConfigured = 'transport_not_configured';

  /// The transport failed to bind or hand back its endpoint.
  static const String transportStartFailed = 'transport_start_failed';

  /// The transport failed while shutting down.
  static const String transportStopFailed = 'transport_stop_failed';

  /// Grant/revoke was attempted while the runtime was not serving.
  static const String runtimeNotRunning = 'runtime_not_running';

  /// The runtime has been disposed and cannot be started again.
  static const String runtimeDisposed = 'runtime_disposed';

  /// The tool name is not part of this session's catalog.
  static const String toolNotFound = 'tool_not_found';

  /// A find query matched no node.
  static const String elementNotFound = 'element_not_found';

  /// A find query matched more than one node; the caller must narrow it.
  static const String ambiguousMatch = 'ambiguous_match';

  /// A tool argument was missing, of the wrong type, or out of range.
  static const String invalidArgument = 'invalid_argument';

  /// An interaction arrived without the `snapshotId` its ref belongs to.
  static const String snapshotRequired = 'snapshot_required';

  /// The snapshot is unknown, superseded, already used, or the app moved on.
  static const String staleSnapshot = 'stale_snapshot';

  /// The ref does not exist in the named snapshot.
  static const String unknownRef = 'unknown_ref';

  /// The node is detached, off screen, disabled, or otherwise unverifiable.
  static const String nodeNotActionable = 'node_not_actionable';

  /// The node does not expose the action the tool needs.
  static const String unsupportedAction = 'unsupported_action';

  /// The node holds sensitive text (password-like) and refuses input.
  static const String nodeSensitive = 'node_sensitive';

  /// The UI refused or failed the action after it was dispatched.
  static const String interactionFailed = 'interaction_failed';

  /// The app did not register an action with that name.
  static const String actionNotFound = 'action_not_found';

  /// A registered business action threw or refused.
  static const String actionFailed = 'action_failed';

  /// The screen could not be captured (no painted layer, protected content).
  static const String captureUnavailable = 'capture_unavailable';

  /// The encoded image exceeds the runtime's byte budget.
  static const String captureTooLarge = 'capture_too_large';

  /// The app's capture policy blocks the current route.
  static const String routeBlocked = 'route_blocked';

  /// The app's privacy policy refuses to serialize this route at all.
  static const String routeDenied = 'route_denied';

  /// The screen changed between two reads, so the answer was discarded.
  static const String routeChanged = 'route_changed';

  /// A registered business action carries a JSON Schema that cannot be used.
  static const String invalidSchema = 'invalid_schema';

  /// Too many requests are in flight; the call was refused before dispatch.
  static const String serverBusy = 'server_busy';

  /// The configured request budget for the window is exhausted.
  static const String rateLimited = 'rate_limited';

  /// A WebView page is not on an origin the app registered.
  static const String originDenied = 'origin_denied';

  /// The app did not register a WebView with that id.
  static const String viewNotFound = 'view_not_found';

  /// The requested image format is not available.
  static const String unsupportedFormat = 'unsupported_format';

  /// Catch-all for unexpected failures.
  static const String unknown = 'unknown_error';
}

const Map<String, ReleaseErrorDescriptor> _descriptors =
    <String, ReleaseErrorDescriptor>{
      ReleaseMcpErrorCode.invalidConfig: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.invalidConfig,
        category: ReleaseMcpErrorCategory.config,
        retryable: false,
        httpLikeStatus: 400,
        message: 'The release runtime configuration is invalid.',
      ),
      ReleaseMcpErrorCode.invalidPermissionId: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.invalidPermissionId,
        category: ReleaseMcpErrorCategory.permission,
        retryable: false,
        httpLikeStatus: 400,
        message: 'The permission identifier is not recognized.',
      ),
      ReleaseMcpErrorCode.authorizationMissing: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.authorizationMissing,
        category: ReleaseMcpErrorCategory.permission,
        retryable: false,
        httpLikeStatus: 403,
        message: 'This configuration requires explicit user authorization.',
      ),
      ReleaseMcpErrorCode.permissionDenied: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.permissionDenied,
        category: ReleaseMcpErrorCategory.permission,
        retryable: false,
        httpLikeStatus: 403,
        message: 'The session does not hold the required permission.',
      ),
      ReleaseMcpErrorCode.invalidStateTransition: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.invalidStateTransition,
        category: ReleaseMcpErrorCategory.state,
        retryable: false,
        httpLikeStatus: 409,
        message:
            'The runtime cannot perform that transition from its '
            'current state.',
      ),
      ReleaseMcpErrorCode.transportNotConfigured: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.transportNotConfigured,
        category: ReleaseMcpErrorCategory.transport,
        retryable: false,
        httpLikeStatus: 501,
        message: 'No MCP transport is attached to the runtime.',
      ),
      ReleaseMcpErrorCode.transportStartFailed: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.transportStartFailed,
        category: ReleaseMcpErrorCategory.transport,
        retryable: true,
        httpLikeStatus: 503,
        message: 'The MCP transport could not be started.',
      ),
      ReleaseMcpErrorCode.transportStopFailed: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.transportStopFailed,
        category: ReleaseMcpErrorCategory.transport,
        retryable: true,
        httpLikeStatus: 503,
        message: 'The MCP transport could not be stopped cleanly.',
      ),
      ReleaseMcpErrorCode.runtimeNotRunning: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.runtimeNotRunning,
        category: ReleaseMcpErrorCategory.state,
        retryable: false,
        httpLikeStatus: 409,
        message: 'The runtime is not running.',
      ),
      ReleaseMcpErrorCode.runtimeDisposed: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.runtimeDisposed,
        category: ReleaseMcpErrorCategory.state,
        retryable: false,
        httpLikeStatus: 409,
        message: 'The runtime has been disposed.',
      ),
      ReleaseMcpErrorCode.toolNotFound: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.toolNotFound,
        category: ReleaseMcpErrorCategory.validation,
        retryable: false,
        httpLikeStatus: 404,
        message: 'That tool is not available in this session.',
      ),
      ReleaseMcpErrorCode.elementNotFound: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.elementNotFound,
        category: ReleaseMcpErrorCategory.state,
        retryable: true,
        httpLikeStatus: 404,
        message: 'No node matched the query.',
      ),
      ReleaseMcpErrorCode.ambiguousMatch: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.ambiguousMatch,
        category: ReleaseMcpErrorCategory.validation,
        retryable: true,
        httpLikeStatus: 409,
        message: 'More than one node matched the query.',
      ),
      ReleaseMcpErrorCode.invalidArgument: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.invalidArgument,
        category: ReleaseMcpErrorCategory.validation,
        retryable: false,
        httpLikeStatus: 400,
        message: 'A tool argument was invalid.',
      ),
      ReleaseMcpErrorCode.snapshotRequired: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.snapshotRequired,
        category: ReleaseMcpErrorCategory.validation,
        retryable: true,
        httpLikeStatus: 400,
        message: 'An interaction needs the snapshot that issued the ref.',
      ),
      ReleaseMcpErrorCode.staleSnapshot: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.staleSnapshot,
        category: ReleaseMcpErrorCategory.state,
        retryable: true,
        httpLikeStatus: 409,
        message: 'That snapshot is no longer current.',
      ),
      ReleaseMcpErrorCode.unknownRef: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.unknownRef,
        category: ReleaseMcpErrorCategory.validation,
        retryable: true,
        httpLikeStatus: 404,
        message: 'No node with that ref in this snapshot.',
      ),
      ReleaseMcpErrorCode.nodeNotActionable: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.nodeNotActionable,
        category: ReleaseMcpErrorCategory.state,
        retryable: true,
        httpLikeStatus: 409,
        message: 'The node is not actionable right now.',
      ),
      ReleaseMcpErrorCode.unsupportedAction: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.unsupportedAction,
        category: ReleaseMcpErrorCategory.validation,
        retryable: false,
        httpLikeStatus: 422,
        message: 'The node does not expose that action.',
      ),
      ReleaseMcpErrorCode.nodeSensitive: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.nodeSensitive,
        category: ReleaseMcpErrorCategory.permission,
        retryable: false,
        httpLikeStatus: 403,
        message: 'Sensitive input is never driven from outside the app.',
      ),
      ReleaseMcpErrorCode.interactionFailed: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.interactionFailed,
        category: ReleaseMcpErrorCategory.execution,
        retryable: true,
        httpLikeStatus: 500,
        message: 'The UI refused or failed the action.',
      ),
      ReleaseMcpErrorCode.actionNotFound: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.actionNotFound,
        category: ReleaseMcpErrorCategory.validation,
        retryable: false,
        httpLikeStatus: 404,
        message: 'That action was not registered by the app.',
      ),
      ReleaseMcpErrorCode.actionFailed: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.actionFailed,
        category: ReleaseMcpErrorCategory.execution,
        retryable: true,
        httpLikeStatus: 500,
        message: 'The business action refused or failed.',
      ),
      ReleaseMcpErrorCode.captureUnavailable: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.captureUnavailable,
        category: ReleaseMcpErrorCategory.capability,
        retryable: true,
        httpLikeStatus: 501,
        message: 'The screen could not be captured.',
      ),
      ReleaseMcpErrorCode.captureTooLarge: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.captureTooLarge,
        category: ReleaseMcpErrorCategory.validation,
        retryable: true,
        httpLikeStatus: 413,
        message: 'The capture exceeds the size budget.',
      ),
      ReleaseMcpErrorCode.routeBlocked: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.routeBlocked,
        category: ReleaseMcpErrorCategory.permission,
        retryable: false,
        httpLikeStatus: 403,
        message: 'Capture is blocked on this screen by app policy.',
      ),
      ReleaseMcpErrorCode.unsupportedFormat: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.unsupportedFormat,
        category: ReleaseMcpErrorCategory.validation,
        retryable: false,
        httpLikeStatus: 415,
        message: 'That image format is not available.',
      ),
      ReleaseMcpErrorCode.routeDenied: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.routeDenied,
        category: ReleaseMcpErrorCategory.permission,
        retryable: false,
        httpLikeStatus: 403,
        message: 'The app privacy policy refuses to read this screen.',
      ),
      ReleaseMcpErrorCode.routeChanged: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.routeChanged,
        category: ReleaseMcpErrorCategory.state,
        retryable: true,
        httpLikeStatus: 409,
        message: 'The screen changed while the request was running.',
      ),
      ReleaseMcpErrorCode.invalidSchema: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.invalidSchema,
        category: ReleaseMcpErrorCategory.config,
        retryable: false,
        httpLikeStatus: 400,
        message: 'A registered action schema is not usable.',
      ),
      ReleaseMcpErrorCode.serverBusy: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.serverBusy,
        category: ReleaseMcpErrorCategory.transport,
        retryable: true,
        httpLikeStatus: 429,
        message: 'The runtime is at its concurrency budget.',
      ),
      ReleaseMcpErrorCode.rateLimited: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.rateLimited,
        category: ReleaseMcpErrorCategory.transport,
        retryable: true,
        httpLikeStatus: 429,
        message: 'The request budget for this window is exhausted.',
      ),
      ReleaseMcpErrorCode.originDenied: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.originDenied,
        category: ReleaseMcpErrorCategory.permission,
        retryable: false,
        httpLikeStatus: 403,
        message: 'That WebView origin is not authorized by the app.',
      ),
      ReleaseMcpErrorCode.viewNotFound: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.viewNotFound,
        category: ReleaseMcpErrorCategory.validation,
        retryable: false,
        httpLikeStatus: 404,
        message: 'No WebView with that id is registered.',
      ),
      ReleaseMcpErrorCode.unknown: ReleaseErrorDescriptor(
        code: ReleaseMcpErrorCode.unknown,
        category: ReleaseMcpErrorCategory.internal,
        retryable: false,
        httpLikeStatus: 500,
        message: 'Unexpected release runtime failure.',
      ),
    };

/// Descriptor for [code], falling back to [ReleaseMcpErrorCode.unknown].
ReleaseErrorDescriptor descriptorForReleaseErrorCode(String code) =>
    _descriptors[code] ?? _descriptors[ReleaseMcpErrorCode.unknown]!;

/// The single exception type the release runtime throws.
///
/// The message is fixed per code — callers cannot supply prose, so it can never
/// echo request data. [details] only carries non-sensitive breadcrumbs such as
/// field names or error *types*. Request bodies, node text, tokens, and user
/// values must never be attached here.
@immutable
final class ReleaseMcpException implements Exception {
  ReleaseMcpException(
    this.code, {
    List<ReleaseConfigProblem> problems = const <ReleaseConfigProblem>[],
    Map<String, Object?> details = const <String, Object?>{},
  }) : _problems = List<ReleaseConfigProblem>.unmodifiable(problems),
       _details = Map<String, Object?>.unmodifiable(details);

  /// Builds the `invalid_config` failure carrying the failed rules.
  factory ReleaseMcpException.invalidConfig(
    List<ReleaseConfigProblem> problems,
  ) => ReleaseMcpException(
    ReleaseMcpErrorCode.invalidConfig,
    problems: problems,
  );

  /// Stable error code; see [ReleaseMcpErrorCode].
  final String code;

  final List<ReleaseConfigProblem> _problems;
  final Map<String, Object?> _details;

  /// Configuration rules that failed, when [code] is `invalid_config`.
  List<ReleaseConfigProblem> get problems => _problems;

  /// Non-sensitive breadcrumbs.
  Map<String, Object?> get details => _details;

  /// Descriptor for [code].
  ReleaseErrorDescriptor get descriptor => descriptorForReleaseErrorCode(code);

  /// Safe, human-readable message: always the fixed text for [code].
  String get message => descriptor.message;

  /// Whether the same call may succeed on retry.
  bool get retryable => descriptor.retryable;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'category': descriptor.category,
    'retryable': descriptor.retryable,
    'httpLikeStatus': descriptor.httpLikeStatus,
    'problems': _problems
        .map((problem) => problem.toJson())
        .toList(growable: false),
    'details': _details,
  };

  @override
  String toString() => 'ReleaseMcpException($code): $message';
}
