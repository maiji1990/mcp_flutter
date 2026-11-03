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
  static const String permission = 'permission';
  static const String state = 'state';
  static const String transport = 'transport';
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
