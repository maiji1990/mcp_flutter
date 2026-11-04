// packages/release_runtime/test/tools/interaction_tools_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'dart:async';

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

import '../support/fake_interaction_driver.dart';
import '../support/fake_snapshot_source.dart';

ReleaseUiNode _node(
  String ref, {
  String type = 'button',
  String? label,
  List<String> actions = const <String>['tap'],
  bool sensitive = false,
}) => ReleaseUiNode(
  ref: ref,
  id: ref.hashCode,
  type: type,
  bounds: const ReleaseUiRect(left: 0, top: 0, right: 100, bottom: 40),
  label: label,
  actions: actions,
  sensitive: sensitive,
  visibleInViewport: true,
  centerInViewport: true,
);

List<ReleaseUiNode> _defaultNodes() => <ReleaseUiNode>[
  _node('s_0', label: 'Pay now'),
  _node('s_1', type: 'textField', actions: const <String>['setText']),
  _node(
    's_2',
    type: 'textField',
    actions: const <String>['setText'],
    sensitive: true,
  ),
];

/// Read and interaction tools over one shared snapshot store.
final class Harness {
  Harness({
    List<ReleaseUiNode>? nodes,
    FakeDriver? driver,
    this.routeName = '/home',
  }) : driver = driver ?? FakeDriver(),
       store = ReleaseSnapshotStore() {
    this.driver.routeName ??= routeName;
    read = ReleaseReadTools(
      source: FakeSnapshotSource(
        nodes: nodes ?? _defaultNodes(),
        routeName: routeName,
      ),
      store: store,
    );
    interaction = ReleaseInteractionTools(store: store, driver: this.driver);
  }

  final String routeName;

  final FakeDriver driver;
  final ReleaseSnapshotStore store;
  late final ReleaseReadTools read;
  late final ReleaseInteractionTools interaction;

  Future<ReleaseToolCallResult> tree() =>
      read.call('ui_get_tree', <String, Object?>{});

  Future<ReleaseToolCallResult> click(String ref, String? snapshotId) =>
      interaction.call('ui_click', <String, Object?>{
        'ref': ref,
        'snapshotId': ?snapshotId,
      });

  Future<ReleaseToolCallResult> type(
    String ref,
    String text,
    String? snapshotId,
  ) => interaction.call('ui_set_text', <String, Object?>{
    'ref': ref,
    'text': text,
    'snapshotId': ?snapshotId,
  });

  Future<ReleaseToolCallResult> scroll(
    String ref,
    String direction,
    String? snapshotId, {
    double? amount,
  }) => interaction.call('ui_scroll', <String, Object?>{
    'ref': ref,
    'direction': direction,
    'amount': ?amount,
    'snapshotId': ?snapshotId,
  });
}

String? _code(ReleaseToolCallResult result) => result.error?.code;
Object? _reason(ReleaseToolCallResult result) =>
    result.error?.details['reason'];

void main() {
  group('ui_click', () {
    test('dispatches a tap for a ref from the current snapshot', () async {
      final h = Harness();
      final tree = await h.tree();

      final result = await h.click('s_0', tree.snapshotId);

      expect(result.success, isTrue, reason: result.error?.message);
      expect(result.snapshotId, tree.snapshotId);
      expect(result.data!['dispatched'], isTrue);
      expect(result.data!['action'], 'tap');
      expect(result.data!['via'], 'semantic_action');
      expect(h.driver.tapped, <String>['s_0']);
    });

    test('a consumed snapshot cannot be used twice', () async {
      final h = Harness();
      final tree = await h.tree();
      await h.click('s_0', tree.snapshotId);

      final second = await h.click('s_0', tree.snapshotId);

      expect(second.success, isFalse);
      expect(_code(second), ReleaseMcpErrorCode.staleSnapshot);
      expect(_reason(second), 'consumed');
      expect(h.driver.tapped, hasLength(1));
    });

    test('a superseded snapshot is refused', () async {
      final h = Harness();
      final first = await h.tree();
      final second = await h.tree();

      final result = await h.click('s_0', first.snapshotId);

      expect(result.success, isFalse);
      expect(_code(result), ReleaseMcpErrorCode.staleSnapshot);
      expect(_reason(result), 'superseded');
      expect(result.snapshotId, first.snapshotId);
      expect(second.snapshotId, isNot(first.snapshotId));
    });

    test('a snapshot the app replaced is refused', () async {
      final h = Harness();
      final tree = await h.tree();
      h.driver.snapshotId = 'ui-99';

      final result = await h.click('s_0', tree.snapshotId);

      expect(_code(result), ReleaseMcpErrorCode.staleSnapshot);
      expect(_reason(result), 'app_moved_on');
    });

    test('a missing snapshotId is refused, not defaulted', () async {
      final h = Harness();
      await h.tree();

      final result = await h.click('s_0', null);

      expect(result.success, isFalse);
      expect(_code(result), ReleaseMcpErrorCode.snapshotRequired);
      expect(h.driver.tapped, isEmpty);
    });

    test('an unknown snapshot id is refused', () async {
      final h = Harness();
      await h.tree();

      final result = await h.click('s_0', 'ui-404');

      expect(_code(result), ReleaseMcpErrorCode.staleSnapshot);
      expect(_reason(result), 'unknown_snapshot');
    });

    test('an unknown ref is refused', () async {
      final h = Harness();
      final tree = await h.tree();

      final result = await h.click('s_99', tree.snapshotId);

      expect(_code(result), ReleaseMcpErrorCode.unknownRef);
      expect(h.driver.tapped, isEmpty);
    });

    test(
      'detached, hidden, and disabled nodes are refused with a reason',
      () async {
        for (final entry in <ReleaseUiNodeState, String>{
          ReleaseUiNodeState.detached: 'detached',
          ReleaseUiNodeState.hidden: 'hidden',
          ReleaseUiNodeState.disabled: 'disabled',
          ReleaseUiNodeState.unknown: 'unknown',
        }.entries) {
          final h = Harness(
            driver: FakeDriver(
              states: <String, ReleaseUiNodeState>{'s_0': entry.key},
            ),
          );
          final tree = await h.tree();

          final result = await h.click('s_0', tree.snapshotId);

          expect(result.success, isFalse, reason: entry.key.wireName);
          expect(_code(result), ReleaseMcpErrorCode.nodeNotActionable);
          expect(_reason(result), entry.value);
          expect(h.driver.tapped, isEmpty);
        }
      },
    );

    test('a node without a tap action is refused', () async {
      final h = Harness(
        nodes: <ReleaseUiNode>[
          _node('s_0', type: 'label', actions: const <String>[]),
        ],
      );
      final tree = await h.tree();

      final result = await h.click('s_0', tree.snapshotId);

      expect(_code(result), ReleaseMcpErrorCode.unsupportedAction);
      expect(result.error!.details['actions'], isEmpty);
    });

    test('driver refusals map onto stable codes', () async {
      final h = Harness(
        driver: FakeDriver(failWith: 'target_outside_viewport'),
      );
      final tree = await h.tree();

      final result = await h.click('s_0', tree.snapshotId);

      expect(_code(result), ReleaseMcpErrorCode.nodeNotActionable);
      expect(_reason(result), 'hidden');
    });

    test(
      'a detached node reported by the driver is stale, not unknown',
      () async {
        final h = Harness(driver: FakeDriver(failWith: 'stale_ref'));
        final tree = await h.tree();

        final result = await h.click('s_0', tree.snapshotId);

        expect(_code(result), ReleaseMcpErrorCode.staleSnapshot);
        expect(_reason(result), 'node_left_tree');
      },
    );

    test(
      'a throwing driver becomes interaction_failed without a stack',
      () async {
        final h = Harness(driver: FakeDriver(throws: true));
        final tree = await h.tree();

        final result = await h.click('s_0', tree.snapshotId);

        expect(_code(result), ReleaseMcpErrorCode.interactionFailed);
        expect(result.error!.details['cause'], 'StateError');
        expect(result.error!.message, isNot(contains('blew up')));
      },
    );

    test(
      'concurrent calls are serialized: one tap, one stale refusal',
      () async {
        final h = Harness();
        final tree = await h.tree();

        final results = await Future.wait(<Future<ReleaseToolCallResult>>[
          h.click('s_0', tree.snapshotId),
          h.click('s_0', tree.snapshotId),
        ]);

        expect(results.where((result) => result.success), hasLength(1));
        expect(
          results.where(
            (result) => _code(result) == ReleaseMcpErrorCode.staleSnapshot,
          ),
          hasLength(1),
        );
        expect(h.driver.tapped, hasLength(1));
      },
    );
  });

  group('ui_set_text', () {
    test('types into a normal text field', () async {
      final h = Harness();
      final tree = await h.tree();

      final result = await h.type('s_1', 'Grace Hopper', tree.snapshotId);

      expect(result.success, isTrue, reason: result.error?.message);
      expect(result.data!['action'], 'setText');
      expect(h.driver.typed, <(String, String)>[('s_1', 'Grace Hopper')]);
      expect(result.toJson().toString(), isNot(contains('Grace Hopper')));
    });

    test('refuses to type into a sensitive field', () async {
      final h = Harness();
      final tree = await h.tree();

      final result = await h.type('s_2', '123456', tree.snapshotId);

      expect(_code(result), ReleaseMcpErrorCode.nodeSensitive);
      expect(result.error!.message, isNot(contains('123456')));
      expect(h.driver.typed, isEmpty);
    });

    test('requires text to be a string', () async {
      final h = Harness();
      final tree = await h.tree();

      final result = await h.interaction.call('ui_set_text', <String, Object?>{
        'ref': 's_1',
        'text': 42,
        'snapshotId': tree.snapshotId,
      });

      expect(_code(result), ReleaseMcpErrorCode.invalidArgument);
    });
  });

  group('ui_scroll', () {
    test('scrolls with a direction and an amount', () async {
      final h = Harness(
        nodes: <ReleaseUiNode>[
          _node('s_0', type: 'list', actions: const <String>['scrollDown']),
        ],
      );
      final tree = await h.tree();

      final result = await h.scroll(
        's_0',
        'down',
        tree.snapshotId,
        amount: 240,
      );

      expect(result.success, isTrue, reason: result.error?.message);
      expect(result.data!['action'], 'scroll_down');
      expect(h.driver.scrolled, <(String, String, double)>[
        ('s_0', 'down', 240),
      ]);
    });

    test('defaults the amount and rejects a bad direction or range', () async {
      final h = Harness(
        nodes: <ReleaseUiNode>[
          _node('s_0', type: 'list', actions: const <String>['scrollDown']),
        ],
      );
      final tree = await h.tree();

      final defaulted = await h.scroll('s_0', 'down', tree.snapshotId);
      expect(defaulted.success, isTrue);
      expect(h.driver.scrolled.single.$3, 300);

      final badDirection = await h.scroll('s_0', 'diagonal', tree.snapshotId);
      expect(_code(badDirection), ReleaseMcpErrorCode.invalidArgument);

      final badAmount = await h.scroll(
        's_0',
        'down',
        tree.snapshotId,
        amount: 0,
      );
      expect(_code(badAmount), ReleaseMcpErrorCode.invalidArgument);
    });

    test('refuses a node with no scroll action', () async {
      final h = Harness();
      final tree = await h.tree();

      final result = await h.scroll('s_0', 'down', tree.snapshotId);

      expect(_code(result), ReleaseMcpErrorCode.unsupportedAction);
    });
  });

  group('snapshot lifecycle', () {
    test(
      'a find query publishes its snapshot and supersedes the tree',
      () async {
        final h = Harness();
        final tree = await h.tree();

        final found = await h.read.call('ui_find_element', <String, Object?>{
          'label': 'Pay now',
        });

        expect(found.success, isTrue);
        expect(h.store.latestId, found.snapshotId);
        expect(h.store.latestId, isNot(tree.snapshotId));

        final staleClick = await h.click('s_0', tree.snapshotId);
        expect(_code(staleClick), ReleaseMcpErrorCode.staleSnapshot);
      },
    );

    test(
      'ui_get_current_page does not disturb the actionable snapshot',
      () async {
        final h = Harness();
        final tree = await h.tree();

        await h.read.call('ui_get_current_page', <String, Object?>{});

        final result = await h.click('s_0', tree.snapshotId);
        expect(result.success, isTrue, reason: result.error?.message);
      },
    );

    test('only what the tree returned is clickable', () async {
      final h = Harness();
      final limited = await h.read.call('ui_get_tree', <String, Object?>{
        'maxNodes': 1,
      });

      final result = await h.click('s_2', limited.snapshotId);

      expect(_code(result), ReleaseMcpErrorCode.unknownRef);
    });
  });

  group('authorization epoch and navigation', () {
    test(
      'a revoked consent refuses a click that waited in the queue',
      () async {
        var granted = true;
        final gate = Completer<void>();
        final driver = FakeDriver()..tapGate = gate;
        final h = Harness(driver: driver);
        final tree = await h.tree();
        final authorization = ReleaseCallAuthorization(
          epoch: 1,
          grantProbe: (permission) =>
              granted && permission == ReleasePermissionId.uiInteract,
        );
        final arguments = <String, Object?>{
          'ref': 's_0',
          'snapshotId': tree.snapshotId,
        };

        final first = h.interaction.call(
          'ui_click',
          arguments,
          authorization: authorization,
        );
        await Future<void>.delayed(Duration.zero);
        final second = h.interaction.call(
          'ui_click',
          arguments,
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
        expect(driver.tapped, <String>['s_0']);
      },
    );

    test('a route change since the snapshot makes the ref stale', () async {
      final h = Harness(routeName: '/home');
      final tree = await h.tree();
      h.driver.routeName = '/wallet';

      final result = await h.click('s_0', tree.snapshotId);

      expect(result.success, isFalse);
      expect(result.error!.code, ReleaseMcpErrorCode.staleSnapshot);
      expect(result.error!.details['reason'], 'route_changed');
      expect(h.driver.tapped, isEmpty);
    });
  });

  group('catalog', () {
    test('the three write tools are declared with ui:interact and require snapshotId', () {
      final h = Harness();
      final tools = h.interaction.tools;

      expect(tools.map((tool) => tool.name), <String>[
        'ui_click',
        'ui_set_text',
        'ui_scroll',
      ]);
      for (final tool in tools) {
        expect(tool.permission, ReleasePermissionId.uiInteract);
        final required = tool.inputSchema['required']! as List<Object?>;
        expect(required, contains('snapshotId'));
      }
    });

    test('the toolbox refuses duplicate tool names', () {
      final h = Harness();

      expect(
        () => ReleaseToolbox(<ReleaseToolSurface>[h.read, h.read]),
        throwsArgumentError,
      );

      final box = ReleaseToolbox(<ReleaseToolSurface>[h.read, h.interaction]);
      expect(box.tools, hasLength(6));
    });
  });
}
