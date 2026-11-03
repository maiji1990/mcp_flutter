// packages/release_runtime/lib/src/lifecycle/runtime_status.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

import '../config/release_mcp_config.dart';
import '../security/permissions.dart';
import 'runtime_lifecycle.dart';

/// Immutable, read-only snapshot of a [ReleaseMcpRuntime].
///
/// Snapshots are cheap value objects: they are what `statusChanges` emits and
/// what a future `runtime_status` MCP tool would serialize. They never contain
/// tokens, request bodies, or node text.
@immutable
final class ReleaseRuntimeStatus {
  const ReleaseRuntimeStatus({
    required this.state,
    required this.isDisposed,
    required this.isReadOnly,
    required this.grantedPermissions,
    required this.config,
    this.endpoint,
    this.startedAt,
    this.errorCode,
  });

  /// Current lifecycle state.
  final ReleaseRuntimeState state;

  /// True once `dispose()` has run.
  final bool isDisposed;

  /// True when the session holds no interactive, capture, or app permission.
  final bool isReadOnly;

  /// Permissions the running session currently holds.
  final ReleasePermissionSet grantedPermissions;

  /// Configuration the runtime was built with.
  final ReleaseMcpConfig config;

  /// URI reported by the transport, when it binds a real endpoint.
  ///
  /// Null while disabled or when the attached transport is inert.
  final Uri? endpoint;

  /// UTC instant the current session started, if it ever did.
  final DateTime? startedAt;

  /// Error code recorded by the last failure, if the state is `error`.
  final String? errorCode;

  /// True when the runtime is serving.
  bool get isServing => state.isServing;

  /// True when a listener is bound (a transport reported an endpoint).
  bool get isListening => endpoint != null;

  /// Redaction-safe JSON view.
  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.wireName,
    'isDisposed': isDisposed,
    'isReadOnly': isReadOnly,
    'grantedPermissions': grantedPermissions.toWireList(),
    'endpoint': endpoint?.toString(),
    'startedAt': startedAt?.toIso8601String(),
    'errorCode': errorCode,
    'config': config.toJson(),
  };

  @override
  String toString() =>
      'ReleaseRuntimeStatus(state: ${state.wireName}, '
      'isReadOnly: $isReadOnly, endpoint: $endpoint, errorCode: $errorCode)';
}
