// packages/release_runtime/lib/src/actions/app_action.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

import '../security/permissions.dart';

/// Handles one business action.
///
/// The argument map is whatever the client sent under `arguments`; the return
/// value becomes `data.result` of the tool call. Return null for "nothing to
/// report".
typedef ReleaseAppActionHandler = Future<Map<String, Object?>?> Function(
  Map<String, Object?> arguments,
);

/// A business action the app itself registers.
///
/// This is the boundary the plan calls for: an app action is not a generic
/// capability an agent discovers — it is a named operation the app chose to
/// expose, with its own permission (`app:<name>`) and its own schema. The
/// runtime never guesses what an action does, and a client cannot call one that
/// was not registered.
@immutable
final class ReleaseAppAction {
  ReleaseAppAction({
    required this.name,
    required this.description,
    required this.handler,
    this.inputSchema = const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
      'additionalProperties': false,
    },
  }) : permission = ReleasePermissionId.app(name);

  /// Slug identifying the action; also the `app:<name>` permission suffix.
  ///
  /// Validated by [ReleasePermissionId.app] at construction, so a bad name
  /// fails where the action is declared, not on the first call.
  final String name;

  /// What the action does, shown to clients.
  final String description;

  /// JSON Schema for [handler]'s argument map.
  final Map<String, Object?> inputSchema;

  /// The app's implementation.
  final ReleaseAppActionHandler handler;

  /// `app:<name>`; requires explicit consent like every other write.
  final ReleasePermissionId permission;

  @override
  String toString() => 'ReleaseAppAction($name)';
}
