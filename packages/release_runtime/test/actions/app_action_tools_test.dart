// packages/release_runtime/test/actions/app_action_tools_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'dart:async';

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

const Map<String, Object?> _invoiceSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'invoiceId': <String, Object?>{'type': 'string', 'maxLength': 64},
    'amount': <String, Object?>{
      'type': 'number',
      'minimum': 1,
      'maximum': 1000,
    },
  },
  'required': <String>['invoiceId'],
  'additionalProperties': false,
};

ReleaseAppAction _action(
  String name, {
  Future<Map<String, Object?>?> Function(Map<String, Object?>)? handler,
  Map<String, Object?> inputSchema = _invoiceSchema,
}) => ReleaseAppAction(
  name: name,
  description: 'Action $name',
  inputSchema: inputSchema,
  handler: handler ?? (arguments) async => <String, Object?>{'ok': true},
);

void main() {
  group('registration', () {
    test('exposes one tool whose schema lists the action names', () {
      final tools = ReleaseAppActionTools(<ReleaseAppAction>[
        _action('pay.invoice'),
        _action('clear_cache'),
      ]);

      expect(tools.tools, hasLength(1));
      final definition = tools.tools.single;
      expect(definition.name, ReleaseAppActionTools.toolName);
      final name =
          (definition.inputSchema['properties']!
                  as Map<String, Object?>)['name']!
              as Map<String, Object?>;
      expect(name['enum'], <String>['pay.invoice', 'clear_cache']);
      expect(definition.permission, isNull);
      expect(tools.registeredNames, <String>['pay.invoice', 'clear_cache']);
    });

    test('rejects duplicate and malformed action names', () {
      expect(
        () => ReleaseAppActionTools(<ReleaseAppAction>[
          _action('pay'),
          _action('pay'),
        ]),
        throwsArgumentError,
      );
      expect(() => _action('Pay Invoice'), throwsA(isA<ReleaseMcpException>()));
    });

    test('rejects a schema that cannot be compiled', () {
      expect(
        () =>
            _action('broken', inputSchema: const <String, Object?>{'type': 5}),
        throwsArgumentError,
      );
    });

    test('resolves each action to its own app permission', () {
      final tools = ReleaseAppActionTools(<ReleaseAppAction>[
        _action('pay.invoice'),
      ]);
      final definition = tools.tools.single;

      expect(
        definition.permissionFor(<String, Object?>{'name': 'pay.invoice'}),
        ReleasePermissionId.app('pay.invoice'),
      );
      expect(
        definition.permissionFor(<String, Object?>{'name': 'unknown'}),
        isNull,
      );
      expect(definition.permissionFor(const <String, Object?>{}), isNull);
    });
  });

  group('app_invoke_action', () {
    test('runs a registered action and returns its payload', () async {
      final seen = <Map<String, Object?>>[];
      final tools = ReleaseAppActionTools(<ReleaseAppAction>[
        _action(
          'pay.invoice',
          handler: (arguments) async {
            seen.add(arguments);
            return <String, Object?>{'status': 'paid'};
          },
        ),
      ]);

      final result = await tools.call(ReleaseAppActionTools.toolName, {
        'name': 'pay.invoice',
        'arguments': <String, Object?>{'invoiceId': 'INV-1'},
      });

      expect(result.success, isTrue, reason: result.error?.message);
      expect(seen.single['invoiceId'], 'INV-1');
      expect(
        (result.data!['result']! as Map<String, Object?>)['status'],
        'paid',
      );
      expect(result.data!['action'], 'pay.invoice');
    });

    test('an action without a payload returns an empty result', () async {
      final tools = ReleaseAppActionTools(<ReleaseAppAction>[
        _action(
          'refresh',
          inputSchema: const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
          handler: (arguments) async => null,
        ),
      ]);

      final result = await tools.call(ReleaseAppActionTools.toolName, {
        'name': 'refresh',
      });

      expect(result.success, isTrue);
      expect(result.data!['result'], isEmpty);
    });

    test('refuses an unregistered action', () async {
      final tools = ReleaseAppActionTools(<ReleaseAppAction>[_action('pay')]);

      final result = await tools.call(ReleaseAppActionTools.toolName, {
        'name': 'delete_everything',
      });

      expect(result.success, isFalse);
      expect(result.error!.code, ReleaseMcpErrorCode.actionNotFound);
      expect(result.error!.message, isNot(contains('delete_everything')));
    });

    test('validates name and arguments', () async {
      final tools = ReleaseAppActionTools(<ReleaseAppAction>[_action('pay')]);

      final noName = await tools.call(
        ReleaseAppActionTools.toolName,
        const <String, Object?>{},
      );
      final badArguments = await tools.call(ReleaseAppActionTools.toolName, {
        'name': 'pay',
        'arguments': 'not-an-object',
      });

      expect(noName.error!.code, ReleaseMcpErrorCode.invalidArgument);
      expect(badArguments.error!.code, ReleaseMcpErrorCode.invalidArgument);
    });

    test('rejects arguments that do not match the schema', () async {
      var calls = 0;
      final tools = ReleaseAppActionTools(<ReleaseAppAction>[
        _action(
          'pay.invoice',
          handler: (arguments) async {
            calls += 1;
            return <String, Object?>{'ok': true};
          },
        ),
      ]);

      final missing = await tools.call(ReleaseAppActionTools.toolName, {
        'name': 'pay.invoice',
        'arguments': <String, Object?>{'amount': 10},
      });
      final wrongType = await tools.call(ReleaseAppActionTools.toolName, {
        'name': 'pay.invoice',
        'arguments': <String, Object?>{'invoiceId': 42},
      });
      final extra = await tools.call(ReleaseAppActionTools.toolName, {
        'name': 'pay.invoice',
        'arguments': <String, Object?>{'invoiceId': 'INV-3', 'admin': true},
      });
      final tooLong = await tools.call(ReleaseAppActionTools.toolName, {
        'name': 'pay.invoice',
        'arguments': <String, Object?>{'invoiceId': 'x' * 65},
      });
      final outOfRange = await tools.call(ReleaseAppActionTools.toolName, {
        'name': 'pay.invoice',
        'arguments': <String, Object?>{'invoiceId': 'INV-4', 'amount': -1},
      });

      for (final result in <ReleaseToolCallResult>[
        missing,
        wrongType,
        extra,
        tooLong,
        outOfRange,
      ]) {
        expect(result.success, isFalse);
        expect(result.error!.code, ReleaseMcpErrorCode.invalidArgument);
        expect(result.error!.details['fields'], isA<List<Object?>>());
        expect(result.toJson().toString(), isNot(contains('admin')));
      }
      expect(calls, 0);
    });

    test('rejects an oversized argument object before validation', () async {
      final tools = ReleaseAppActionTools(<ReleaseAppAction>[
        _action('pay.invoice'),
      ], maxArgumentBytes: 128);

      final result = await tools.call(ReleaseAppActionTools.toolName, {
        'name': 'pay.invoice',
        'arguments': <String, Object?>{'invoiceId': 'x' * 200},
      });

      expect(result.error!.code, ReleaseMcpErrorCode.invalidArgument);
      expect(result.error!.details['field'], 'arguments');
      expect(result.toJson().toString(), isNot(contains('xxxx')));
    });

    test('a throwing action becomes action_failed without its text', () async {
      final tools = ReleaseAppActionTools(<ReleaseAppAction>[
        _action(
          'pay',
          inputSchema: const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
          handler: (arguments) async => throw StateError('card declined 4111'),
        ),
      ]);

      final result = await tools.call(ReleaseAppActionTools.toolName, {
        'name': 'pay',
      });

      expect(result.success, isFalse);
      expect(result.error!.code, ReleaseMcpErrorCode.actionFailed);
      expect(result.error!.details['cause'], 'StateError');
      expect(result.toJson().toString(), isNot(contains('4111')));
    });

    test('serializes concurrent actions', () async {
      var running = 0;
      var maxRunning = 0;
      final tools = ReleaseAppActionTools(<ReleaseAppAction>[
        _action(
          'slow',
          inputSchema: const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
          handler: (arguments) async {
            running += 1;
            maxRunning = running > maxRunning ? running : maxRunning;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            running -= 1;
            return <String, Object?>{'ok': true};
          },
        ),
      ]);

      final results = await Future.wait(<Future<ReleaseToolCallResult>>[
        tools.call(ReleaseAppActionTools.toolName, {'name': 'slow'}),
        tools.call(ReleaseAppActionTools.toolName, {'name': 'slow'}),
      ]);

      expect(results.every((result) => result.success), isTrue);
      expect(maxRunning, 1);
    });

    test(
      'a revoked consent refuses an action that waited in the queue',
      () async {
        var granted = true;
        var calls = 0;
        final gate = Completer<void>();
        final tools = ReleaseAppActionTools(<ReleaseAppAction>[
          ReleaseAppAction(
            name: 'slow',
            description: 'blocks until the test releases it',
            inputSchema: const <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{},
              'additionalProperties': false,
            },
            handler: (arguments) async {
              calls += 1;
              await gate.future;
              return <String, Object?>{'ok': true};
            },
          ),
        ]);
        final authorization = ReleaseCallAuthorization(
          epoch: 1,
          grantProbe: (permission) =>
              granted && permission == ReleasePermissionId.app('slow'),
        );

        final first = tools.call(
          ReleaseAppActionTools.toolName,
          <String, Object?>{'name': 'slow'},
          authorization: authorization,
        );
        await Future<void>.delayed(Duration.zero);
        final second = tools.call(
          ReleaseAppActionTools.toolName,
          <String, Object?>{'name': 'slow'},
          authorization: authorization,
        );
        granted = false;
        gate.complete();

        final firstResult = await first;
        final secondResult = await second;

        expect(firstResult.success, isTrue, reason: firstResult.error?.message);
        expect(secondResult.success, isFalse);
        expect(secondResult.error!.code, ReleaseMcpErrorCode.permissionDenied);
        expect(secondResult.error!.details['reason'], 'authorization_changed');
        expect(calls, 1);
      },
    );

    test('an unknown tool name is refused', () async {
      final tools = ReleaseAppActionTools(<ReleaseAppAction>[_action('pay')]);

      final result = await tools.call('app_other', const <String, Object?>{});

      expect(result.error!.code, ReleaseMcpErrorCode.toolNotFound);
    });
  });
}
