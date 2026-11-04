// packages/release_runtime_flutter/test/flutter_interaction_driver_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter/material.dart';
import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:flutter_mcp_toolkit_release_flutter/flutter_mcp_toolkit_release_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [body] with semantics enabled and disposes the handle before the test
/// binding's end-of-test audit.
Future<T> _withSemantics<T>(
  WidgetTester tester,
  Future<T> Function() body,
) async {
  final handle = tester.ensureSemantics();
  try {
    return await body();
  } finally {
    handle.dispose();
  }
}

/// Drives frames until [pending] completes.
///
/// The snapshot and gesture paths await `endOfFrame`; in a widget test frames
/// only run inside `pump`, so a bare `await` deadlocks. The loop also bounds
/// the wait, so a call that never settles fails the test instead of hanging CI.
Future<T> _pumpUntil<T>(WidgetTester tester, Future<T> pending) async {
  var completed = false;
  late T value;
  Object? error;
  StackTrace? stack;
  pending.then(
    (T result) {
      completed = true;
      value = result;
    },
    onError: (Object failure, StackTrace trace) {
      completed = true;
      error = failure;
      stack = trace;
    },
  );

  for (var frame = 0; frame < 240 && !completed; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }

  if (!completed) {
    throw StateError('The call did not complete after 240 frames.');
  }
  if (error != null) {
    Error.throwWithStackTrace(error!, stack!);
  }
  return value;
}

/// A read + interaction pair over one store, wired to the real driver.
final class _Tools {
  _Tools() {
    store = ReleaseSnapshotStore();
    read = ReleaseReadTools(
      source: FlutterReleaseUiSnapshotSource(),
      store: store,
    );
    interaction = ReleaseInteractionTools(
      store: store,
      driver: const FlutterReleaseUiInteractionDriver(),
    );
  }

  late final ReleaseSnapshotStore store;
  late final ReleaseReadTools read;
  late final ReleaseInteractionTools interaction;

  Future<ReleaseToolCallResult> tree() =>
      read.call('ui_get_tree', <String, Object?>{});

  Future<ReleaseToolCallResult> click(String ref, String snapshotId) =>
      interaction.call('ui_click', <String, Object?>{
        'ref': ref,
        'snapshotId': snapshotId,
      });

  Future<ReleaseToolCallResult> type(
    String ref,
    String text,
    String snapshotId,
  ) => interaction.call('ui_set_text', <String, Object?>{
    'ref': ref,
    'text': text,
    'snapshotId': snapshotId,
  });

  Future<ReleaseToolCallResult> scroll(
    String ref,
    String direction,
    String snapshotId,
  ) => interaction.call('ui_scroll', <String, Object?>{
    'ref': ref,
    'direction': direction,
    'snapshotId': snapshotId,
  });
}

List<Map<String, Object?>> _nodes(ReleaseToolCallResult tree) =>
    (tree.data!['nodes']! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?>? _nodeWhere(
  ReleaseToolCallResult tree,
  bool Function(Map<String, Object?>) test,
) {
  for (final node in _nodes(tree)) {
    if (test(node)) {
      return node;
    }
  }
  return null;
}

void main() {
  testWidgets('ui_click taps a button and the app state changes', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: <Widget>[
                  ElevatedButton(
                    onPressed: () => setState(() => count += 1),
                    child: Text('Increment $count'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tools = _Tools();
      final tree = await _pumpUntil(tester, tools.tree());
      expect(tree.success, isTrue);

      final button = _nodeWhere(
        tree,
        (node) => (node['label'] as String?)?.contains('Increment') ?? false,
      );
      expect(button, isNotNull, reason: 'button node must be in the tree');

      final click = await _pumpUntil(
        tester,
        tools.click(button!['ref']! as String, tree.snapshotId!),
      );

      expect(click.success, isTrue, reason: click.error?.message);
      expect(click.data!['dispatched'], isTrue);
      await tester.pumpAndSettle();
      expect(count, 1);

      // The snapshot was consumed: acting on it again must be refused rather
      // than tapping whatever moved under the old ref.
      final again = await _pumpUntil(
        tester,
        tools.click(button['ref']! as String, tree.snapshotId!),
      );
      expect(again.success, isFalse);
      expect(again.error!.code, ReleaseMcpErrorCode.staleSnapshot);
      expect(count, 1);
    });
  });

  testWidgets('ui_set_text writes into a field and reads back', (tester) async {
    await _withSemantics(tester, () async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tools = _Tools();
      final tree = await _pumpUntil(tester, tools.tree());
      // Flutter only publishes the setText action once a field has focus, so
      // the tool identifies a field by role; the driver focuses before typing.
      final field = _nodeWhere(tree, (node) => node['type'] == 'textField');
      expect(field, isNotNull, reason: 'the text field must be in the tree');

      final typed = await _pumpUntil(
        tester,
        tools.type(field!['ref']! as String, 'Ada Lovelace', tree.snapshotId!),
      );

      expect(typed.success, isTrue, reason: typed.error?.message);
      await tester.pumpAndSettle();
      expect(controller.text, 'Ada Lovelace');

      final after = await _pumpUntil(tester, tools.tree());
      final updated = _nodeWhere(
        after,
        (node) => (node['value'] as String?) == 'Ada Lovelace',
      );
      expect(updated, isNotNull);
    });
  });

  testWidgets('ui_set_text refuses an obscured field', (tester) async {
    await _withSemantics(tester, () async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextField(
              obscureText: true,
              decoration: InputDecoration(labelText: 'PIN'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tools = _Tools();
      final tree = await _pumpUntil(tester, tools.tree());
      final field = _nodeWhere(
        tree,
        (node) => (node['sensitive'] as bool?) ?? false,
      );
      expect(field, isNotNull, reason: 'the PIN field is obscured');

      final typed = await _pumpUntil(
        tester,
        tools.type(field!['ref']! as String, '123456', tree.snapshotId!),
      );

      expect(typed.success, isFalse);
      expect(typed.error!.code, ReleaseMcpErrorCode.nodeSensitive);
      expect(typed.toJson().toString(), isNot(contains('123456')));
    });
  });

  testWidgets('ui_scroll moves a list through its scroll action', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: 60,
              itemBuilder: (context, index) =>
                  SizedBox(height: 80, child: Text('Row $index')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tools = _Tools();
      final tree = await _pumpUntil(tester, tools.tree());
      final scrollable = _nodeWhere(
        tree,
        (node) =>
            (node['actions'] as List<Object?>?)?.any(
              (action) => action is String && action.startsWith('scroll'),
            ) ??
            false,
      );
      expect(
        scrollable,
        isNotNull,
        reason: 'a scrollable node must be present',
      );

      final scrolled = await _pumpUntil(
        tester,
        tools.scroll(scrollable!['ref']! as String, 'down', tree.snapshotId!),
      );

      expect(scrolled.success, isTrue, reason: scrolled.error?.message);
      expect(scrolled.data!['action'], 'scroll_down');
    });
  });
}
