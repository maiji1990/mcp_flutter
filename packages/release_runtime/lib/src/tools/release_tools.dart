// packages/release_runtime/lib/src/tools/release_tools.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

import '../security/permissions.dart';

/// One tool the runtime can offer.
///
/// Deliberately transport-neutral: the HTTP transport turns these into
/// `mcp_server` tool registrations, and a future stdio or test harness can do
/// something else with the same definitions.
@immutable
final class ReleaseToolDefinition {
  const ReleaseToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.permission,
  });

  /// Wire name, for example `ui_get_tree`.
  final String name;

  /// Description shown to the client.
  final String description;

  /// JSON Schema (root type `object`) for the arguments.
  final Map<String, Object?> inputSchema;

  /// Permission a session must hold to call this tool.
  final ReleasePermissionId permission;
}

/// Non-sensitive failure payload of a tool call.
@immutable
final class ReleaseToolError {
  const ReleaseToolError(this.code, this.message, {this.details = const {}});

  /// Stable code, for example `element_not_found`.
  final String code;

  /// Fixed, non-sensitive sentence.
  final String message;

  /// Breadcrumbs: field names, counts, candidate refs. Never node text.
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (details.isNotEmpty) 'details': details,
  };
}

/// The uniform answer every release tool returns.
///
/// Tool-level failures are `success: false` payloads rather than MCP protocol
/// errors, so a client can read the reason and correct itself (the MCP spec's
/// own guidance for `isError`).
@immutable
final class ReleaseToolCallResult {
  const ReleaseToolCallResult({
    required this.requestId,
    required this.success,
    this.snapshotId,
    this.data,
    this.error,
  });

  /// Correlates a call with its answer.
  final String requestId;

  final bool success;

  /// Snapshot the answer refers to, when it refers to one.
  final String? snapshotId;

  final Map<String, Object?>? data;

  final ReleaseToolError? error;

  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'success': success,
    if (snapshotId != null) 'snapshotId': snapshotId,
    if (data != null) 'data': data,
    if (error != null) 'error': error!.toJson(),
  };
}

/// The tools a runtime exposes.
///
/// A surface only *answers* calls; who may call what, and whether the runtime
/// is serving at all, is decided by `ReleaseMcpRuntime` before it delegates.
abstract interface class ReleaseToolSurface {
  /// Definitions, in the order clients should see them.
  List<ReleaseToolDefinition> get tools;

  /// Executes [name] with [arguments].
  ///
  /// Implementations return [ReleaseToolCallResult] with `success: false` for
  /// ordinary refusals and may throw for programmer errors; the runtime maps a
  /// throw onto `unknown_error` without leaking the stack.
  Future<ReleaseToolCallResult> call(
    String name,
    Map<String, Object?> arguments,
  );
}
