// packages/release_runtime/lib/src/actions/app_action.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:json_schema/json_schema.dart';
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

/// Outcome of validating one call's arguments.
@immutable
final class ReleaseAppActionValidation {
  const ReleaseAppActionValidation.valid()
    : isValid = true,
      failedFields = const <String>[];

  const ReleaseAppActionValidation.invalid(this.failedFields) : isValid = false;

  /// True when the arguments satisfy the action's schema.
  final bool isValid;

  /// JSON-pointer-ish paths of fields that failed, capped and value-free.
  ///
  /// Only paths cross back to the client, never the offending value and never
  /// the validator's prose (which can quote the instance).
  final List<String> failedFields;
}

/// A business action the app itself registers.
///
/// This is the boundary the plan calls for: an app action is not a generic
/// capability an agent discovers — it is a named operation the app chose to
/// expose, with its own permission (`app:<name>`) and its own schema. The
/// runtime never guesses what an action does, and a client cannot call one that
/// was not registered.
///
/// Since PR-09 the schema is **enforced**: it is compiled at registration (a
/// broken schema fails where the action is declared, not on the first call) and
/// every call is validated before the handler runs. Schema validation is a type
/// and shape check, not authorization: the handler still owns business rules.
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
  }) : permission = ReleasePermissionId.app(name),
       _schema = _compile(name, inputSchema);

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

  final JsonSchema _schema;

  /// Validates [arguments] against [inputSchema].
  ReleaseAppActionValidation validate(Map<String, Object?> arguments) {
    final results = _schema.validate(arguments);
    if (results.isValid) {
      return const ReleaseAppActionValidation.valid();
    }
    final paths = <String>[];
    for (final error in results.errors) {
      final path = error.instancePath.isEmpty ? '/' : error.instancePath;
      if (!paths.contains(path)) {
        paths.add(path);
      }
      if (paths.length == 5) {
        break;
      }
    }
    return ReleaseAppActionValidation.invalid(paths);
  }

  /// Compiles the schema once, synchronously. Remote `$ref` resolution is not
  /// available on this path, which is deliberate: a release app must not fetch
  /// a schema over the network to validate a local call.
  static JsonSchema _compile(String name, Map<String, Object?> schema) {
    try {
      return JsonSchema.create(schema);
    } on Object catch (error) {
      throw ArgumentError.value(
        name,
        'inputSchema',
        'not a usable JSON Schema (${error.runtimeType})',
      );
    }
  }

  @override
  String toString() => 'ReleaseAppAction($name)';
}
