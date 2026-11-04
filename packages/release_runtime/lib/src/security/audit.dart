// packages/release_runtime/lib/src/security/audit.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

/// One redaction-safe record of a tool call.
///
/// Carries the decision and argument *shapes*, never values, tokens, or node
/// text. A sink is optional and must not throw; the runtime never lets an audit
/// failure break a tool call.
@immutable
final class ReleaseAuditEvent {
  const ReleaseAuditEvent({
    required this.tool,
    required this.allowed,
    required this.at,
    this.permission,
    this.reason,
    this.argumentKeys = const <String>[],
    this.epoch = 0,
  });

  final String tool;
  final bool allowed;
  final DateTime at;
  final String? permission;
  final String? reason;
  final List<String> argumentKeys;
  final int epoch;

  Map<String, Object?> toJson() => <String, Object?>{
    'tool': tool,
    'allowed': allowed,
    'at': at.toUtc().toIso8601String(),
    if (permission != null) 'permission': permission,
    if (reason != null) 'reason': reason,
    if (argumentKeys.isNotEmpty) 'argumentKeys': argumentKeys,
    'epoch': epoch,
  };

  @override
  String toString() => 'ReleaseAuditEvent($tool, allowed: $allowed)';
}

/// Receives one event per completed (or refused) tool call.
typedef ReleaseAuditSink = void Function(ReleaseAuditEvent event);
