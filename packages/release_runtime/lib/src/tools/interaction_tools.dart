// packages/release_runtime/lib/src/tools/interaction_tools.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import '../errors/release_mcp_error.dart';
import '../security/permissions.dart';
import '../ui/interaction_driver.dart';
import '../ui/release_ui_types.dart';
import 'release_tools.dart';
import 'snapshot_store.dart';

/// Whether a call may proceed, or the refusal to return instead.
sealed class _Validation {
  const _Validation();
}

final class _Valid extends _Validation {
  const _Valid(this.node);

  final ReleaseUiNode node;
}

final class _Invalid extends _Validation {
  const _Invalid(this.result);

  final ReleaseToolCallResult result;
}

/// The write tools of release MCP v1: `ui_click`, `ui_set_text`, `ui_scroll`.
///
/// Every one of them requires `ui:interact` *and* a `snapshotId`. The ref alone
/// is never enough: refs are positional strings re-issued by every snapshot, so
/// acting on an old one is how an agent clicks whatever replaced the button it
/// meant. Validation happens twice — before queueing and again inside the
/// queue — because the tree can change while a call waits its turn.
///
/// A successful call means the action was *dispatched*. Whether the business
/// step happened is a separate question, answered by the next `ui_get_tree`.
/// Consuming the snapshot enforces that: the next interaction needs a fresh
/// read, so it acts on what is actually on screen.
final class ReleaseInteractionTools implements ReleaseToolSurface {
  ReleaseInteractionTools({
    required this.store,
    required this.driver,
    this.defaultScrollAmount = 300,
    this.maxScrollAmount = 5000,
  });

  /// Published snapshots; only the latest unused one is actionable.
  final ReleaseSnapshotStore store;

  /// Performs the action on the UI isolate.
  final ReleaseUiInteractionDriver driver;

  /// Distance used when `amount` is omitted.
  final double defaultScrollAmount;

  /// Hard ceiling on a requested scroll distance.
  final double maxScrollAmount;

  Future<void> _queue = Future<void>.value();
  int _requests = 0;

  @override
  List<ReleaseToolDefinition> get tools => <ReleaseToolDefinition>[
    const ReleaseToolDefinition(
      name: 'ui_click',
      description:
          'Tap one node from a fresh snapshot. Requires ui:interact, the ref, '
          'and the snapshotId that issued it.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'ref': <String, Object?>{'type': 'string'},
          'snapshotId': <String, Object?>{'type': 'string'},
        },
        'required': <String>['ref', 'snapshotId'],
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.uiInteract,
    ),
    const ReleaseToolDefinition(
      name: 'ui_set_text',
      description:
          'Replace the text of an input node from a fresh snapshot. Refuses '
          'sensitive (password-like) fields. Requires ui:interact.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'ref': <String, Object?>{'type': 'string'},
          'text': <String, Object?>{'type': 'string'},
          'snapshotId': <String, Object?>{'type': 'string'},
        },
        'required': <String>['ref', 'text', 'snapshotId'],
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.uiInteract,
    ),
    const ReleaseToolDefinition(
      name: 'ui_scroll',
      description:
          'Scroll the node (or its scrollable ancestor) from a fresh snapshot. '
          'Requires ui:interact.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'ref': <String, Object?>{'type': 'string'},
          'direction': <String, Object?>{
            'type': 'string',
            'enum': <String>['up', 'down', 'left', 'right'],
          },
          'amount': <String, Object?>{
            'type': 'number',
            'minimum': 1,
            'maximum': 5000,
          },
          'snapshotId': <String, Object?>{'type': 'string'},
        },
        'required': <String>['ref', 'direction', 'snapshotId'],
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.uiInteract,
    ),
  ];

  @override
  Future<ReleaseToolCallResult> call(
    String name,
    Map<String, Object?> arguments,
  ) {
    switch (name) {
      case 'ui_click':
        return _click(arguments);
      case 'ui_set_text':
        return _setText(arguments);
      case 'ui_scroll':
        return _scroll(arguments);
      default:
        return Future<ReleaseToolCallResult>.value(
          _refusal(
            _nextRequestId(),
            ReleaseMcpErrorCode.toolNotFound,
            'Call tools/list for the catalog.',
          ),
        );
    }
  }

  Future<ReleaseToolCallResult> _click(Map<String, Object?> arguments) {
    final requestId = _nextRequestId();
    return _execute(
      requestId: requestId,
      snapshotId: _readString(arguments, 'snapshotId'),
      action: 'tap',
      validate: () => _validate(
        requestId: requestId,
        arguments: arguments,
        capability: (node) => node.actions.contains('tap'),
      ),
      perform: (node) => driver.tap(node.ref),
    );
  }

  Future<ReleaseToolCallResult> _setText(Map<String, Object?> arguments) {
    final requestId = _nextRequestId();
    final text = arguments['text'];
    if (text is! String) {
      return Future<ReleaseToolCallResult>.value(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.invalidArgument,
          'text must be a string.',
        ),
      );
    }

    return _execute(
      requestId: requestId,
      snapshotId: _readString(arguments, 'snapshotId'),
      action: 'setText',
      validate: () => _validate(
        requestId: requestId,
        arguments: arguments,
        rejectSensitive: true,
        capability: (node) =>
            node.type == 'textField' || node.actions.contains('setText'),
      ),
      perform: (node) => driver.setText(node.ref, text),
    );
  }

  Future<ReleaseToolCallResult> _scroll(Map<String, Object?> arguments) {
    final requestId = _nextRequestId();

    final directionValue = _readString(arguments, 'direction');
    final direction = directionValue == null
        ? null
        : ReleaseScrollDirection.tryParse(directionValue);
    if (direction == null) {
      return Future<ReleaseToolCallResult>.value(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.invalidArgument,
          'direction must be one of up, down, left, right.',
        ),
      );
    }

    final rawAmount = arguments['amount'];
    final amount = switch (rawAmount) {
      null => defaultScrollAmount,
      final num value => value.toDouble(),
      _ => null,
    };
    if (amount == null || amount <= 0 || amount > maxScrollAmount) {
      return Future<ReleaseToolCallResult>.value(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.invalidArgument,
          'amount must be a number between 1 and $maxScrollAmount.',
        ),
      );
    }

    return _execute(
      requestId: requestId,
      snapshotId: _readString(arguments, 'snapshotId'),
      action: 'scroll_${direction.wireName}',
      validate: () => _validate(
        requestId: requestId,
        arguments: arguments,
        capability: (node) =>
            node.actions.any((action) => action.startsWith('scroll')),
      ),
      perform: (node) => driver.scroll(node.ref, direction, amount: amount),
    );
  }

  /// Runs the action only after every earlier interaction finished, and
  /// re-validates inside the queue.
  Future<ReleaseToolCallResult> _execute({
    required String requestId,
    required String? snapshotId,
    required String action,
    required Future<_Validation> Function() validate,
    required Future<ReleaseDriverResult> Function(ReleaseUiNode node) perform,
  }) {
    final result = _queue.then((_) async {
      final validation = await validate();
      if (validation is _Invalid) {
        return validation.result;
      }
      final node = (validation as _Valid).node;

      final ReleaseDriverResult outcome;
      try {
        outcome = await perform(node);
      } catch (error) {
        return _refusal(
          requestId,
          ReleaseMcpErrorCode.interactionFailed,
          'The action could not be performed.',
          snapshotId: snapshotId,
          details: <String, Object?>{'cause': error.runtimeType.toString()},
        );
      }

      if (!outcome.ok) {
        return _fromDriverFailure(
          requestId: requestId,
          node: node,
          snapshotId: snapshotId,
          outcome: outcome,
        );
      }

      store.consumeLatest();
      return ReleaseToolCallResult(
        requestId: requestId,
        success: true,
        snapshotId: snapshotId,
        data: <String, Object?>{
          'dispatched': true,
          'ref': node.ref,
          'action': action,
          ...outcome.details,
        },
      );
    });
    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<_Validation> _validate({
    required String requestId,
    required Map<String, Object?> arguments,
    required bool Function(ReleaseUiNode node) capability,
    bool rejectSensitive = false,
  }) async {
    final snapshotId = _readString(arguments, 'snapshotId');
    if (snapshotId == null) {
      return _Invalid(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.snapshotRequired,
          'Pass the snapshotId that issued the ref.',
        ),
      );
    }

    final ref = _readString(arguments, 'ref');
    if (ref == null) {
      return _Invalid(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.invalidArgument,
          'ref is required.',
        ),
      );
    }

    if (!store.contains(snapshotId)) {
      return _Invalid(_stale(requestId, snapshotId, 'unknown_snapshot'));
    }
    if (!store.isUsable(snapshotId)) {
      return _Invalid(
        _stale(
          requestId,
          snapshotId,
          store.latestId == snapshotId ? 'consumed' : 'superseded',
        ),
      );
    }
    if (!await driver.isSnapshotCurrent(snapshotId)) {
      return _Invalid(_stale(requestId, snapshotId, 'app_moved_on'));
    }

    final node = store.nodeById(snapshotId, ref);
    if (node == null) {
      return _Invalid(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.unknownRef,
          'No node with that ref in this snapshot.',
          snapshotId: snapshotId,
          details: <String, Object?>{'ref': ref},
        ),
      );
    }

    final state = await driver.inspect(ref);
    if (state != ReleaseUiNodeState.attached) {
      return _Invalid(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.nodeNotActionable,
          'The node is not actionable right now.',
          snapshotId: snapshotId,
          details: <String, Object?>{'ref': ref, 'reason': state.wireName},
        ),
      );
    }

    // Sensitive input is refused before capability: the reason a caller must
    // hear is "never type into this", not "that action is missing".
    if (rejectSensitive && node.sensitive) {
      return _Invalid(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.nodeSensitive,
          'Refusing to type into a sensitive field.',
          snapshotId: snapshotId,
          details: <String, Object?>{'ref': ref},
        ),
      );
    }

    // Capability comes from the snapshot metadata, not the live action set:
    // Flutter only publishes `setText` once a field has focus, and the driver
    // focuses the field it is about to type into.
    if (!capability(node)) {
      return _Invalid(
        _refusal(
          requestId,
          ReleaseMcpErrorCode.unsupportedAction,
          'The node does not expose that action.',
          snapshotId: snapshotId,
          details: <String, Object?>{
            'ref': ref,
            'type': node.type,
            'actions': node.actions,
          },
        ),
      );
    }

    return _Valid(node);
  }

  ReleaseToolCallResult _fromDriverFailure({
    required String requestId,
    required ReleaseUiNode node,
    required String? snapshotId,
    required ReleaseDriverResult outcome,
  }) {
    final token = outcome.error ?? 'interaction_failed';
    final (String code, String reason) = switch (token) {
      'ref_not_found' => (ReleaseMcpErrorCode.unknownRef, token),
      'stale_ref' => (ReleaseMcpErrorCode.staleSnapshot, 'node_left_tree'),
      'target_disabled' => (ReleaseMcpErrorCode.nodeNotActionable, 'disabled'),
      'target_outside_viewport' => (
        ReleaseMcpErrorCode.nodeNotActionable,
        'hidden',
      ),
      'no_bounds_for_ref' => (
        ReleaseMcpErrorCode.nodeNotActionable,
        'no_bounds',
      ),
      'not_a_text_field' ||
      'no_editable_state' ||
      'unsupported_scroll_action' ||
      'no_scrollable_at_point' ||
      'web_gesture_not_supported' => (
        ReleaseMcpErrorCode.unsupportedAction,
        token,
      ),
      _ => (ReleaseMcpErrorCode.interactionFailed, token),
    };

    return _refusal(
      requestId,
      code,
      'The action was refused.',
      snapshotId: snapshotId,
      details: <String, Object?>{'ref': node.ref, 'reason': reason},
    );
  }

  ReleaseToolCallResult _stale(
    String requestId,
    String snapshotId,
    String reason,
  ) => _refusal(
    requestId,
    ReleaseMcpErrorCode.staleSnapshot,
    'Take a fresh snapshot and use refs from it.',
    snapshotId: snapshotId,
    details: <String, Object?>{'reason': reason},
  );

  ReleaseToolCallResult _refusal(
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

  String _nextRequestId() => 'req_${++_requests}';
}

String? _readString(Map<String, Object?> arguments, String key) {
  final raw = arguments[key];
  if (raw is! String) {
    return null;
  }
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}
