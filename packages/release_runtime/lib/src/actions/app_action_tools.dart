// packages/release_runtime/lib/src/actions/app_action_tools.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import '../errors/release_mcp_error.dart';
import '../tools/release_tools.dart';
import 'app_action.dart';

/// Exposes the app's registered business actions as one MCP tool,
/// `app_invoke_action`.
///
/// One tool, many permissions: the permission a call needs depends on the
/// `name` it passes, which is why the tool definition carries a resolver rather
/// than a fixed permission. An unregistered name resolves to "no permission
/// required", which is safe because the surface refuses it before anything
/// runs — the client gets `action_not_found`, not a misleading
/// `permission_denied`.
///
/// Calls are serialized: two business actions at once would race on app state
/// the runtime cannot see.
final class ReleaseAppActionTools implements ReleaseToolSurface {
  ReleaseAppActionTools(Iterable<ReleaseAppAction> actions) {
    for (final action in actions) {
      if (_actions.containsKey(action.name)) {
        throw ArgumentError.value(
          action.name,
          'actions',
          'Duplicate app action name',
        );
      }
      _actions[action.name] = action;
    }
  }

  /// Wire name of the single tool this surface exposes.
  static const String toolName = 'app_invoke_action';

  final Map<String, ReleaseAppAction> _actions = <String, ReleaseAppAction>{};
  Future<void> _queue = Future<void>.value();
  int _requests = 0;

  /// Registered action names, in registration order.
  List<String> get registeredNames => List<String>.unmodifiable(_actions.keys);

  @override
  List<ReleaseToolDefinition> get tools => <ReleaseToolDefinition>[
    ReleaseToolDefinition(
      name: toolName,
      description:
          'Invoke a business action the app registered. Each action needs its '
          'own app:<name> consent and validates its own arguments.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string', 'enum': registeredNames},
          'arguments': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
          },
        },
        'required': <String>['name'],
        'additionalProperties': false,
      },
      permission: null,
      permissionResolver: (arguments) {
        final name = arguments['name'];
        if (name is! String) {
          return null;
        }
        return _actions[name]?.permission;
      },
    ),
  ];

  @override
  Future<ReleaseToolCallResult> call(
    String name,
    Map<String, Object?> arguments,
  ) {
    final requestId = 'req_${++_requests}';
    if (name != toolName) {
      return Future<ReleaseToolCallResult>.value(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.toolNotFound,
          'Call tools/list for the catalog.',
        ),
      );
    }

    final actionName = arguments['name'];
    if (actionName is! String || actionName.trim().isEmpty) {
      return Future<ReleaseToolCallResult>.value(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.invalidArgument,
          'name of the action is required.',
        ),
      );
    }

    final action = _actions[actionName];
    if (action == null) {
      return Future<ReleaseToolCallResult>.value(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.actionNotFound,
          'Call tools/list to see the action names this app registered.',
          details: <String, Object?>{'registeredCount': _actions.length},
        ),
      );
    }

    final rawArguments = arguments['arguments'];
    final callArguments = switch (rawArguments) {
      null => const <String, Object?>{},
      final Map<Object?, Object?> value => value.cast<String, Object?>(),
      _ => null,
    };
    if (callArguments == null) {
      return Future<ReleaseToolCallResult>.value(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.invalidArgument,
          'arguments must be an object.',
        ),
      );
    }

    final result = _queue.then((_) async {
      try {
        final output = await action.handler(callArguments);
        return ReleaseToolCallResult(
          requestId: requestId,
          success: true,
          data: <String, Object?>{
            'action': action.name,
            'result': output ?? const <String, Object?>{},
          },
        );
      } catch (error) {
        return _refusal(
          requestId,
          ReleaseMcpErrorCode.actionFailed,
          'The app refused or failed that action.',
          details: <String, Object?>{'cause': error.runtimeType.toString()},
        );
      }
    });
    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  ReleaseToolCallResult _refusal(
    String requestId,
    String code,
    String hint, {
    Map<String, Object?> details = const <String, Object?>{},
  }) => ReleaseToolCallResult(
    requestId: requestId,
    success: false,
    error: ReleaseToolError(
      code,
      '${descriptorForReleaseErrorCode(code).message} $hint',
      details: details,
    ),
  );
}
