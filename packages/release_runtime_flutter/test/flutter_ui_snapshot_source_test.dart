// packages/release_runtime_flutter/test/flutter_ui_snapshot_source_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter/material.dart';
import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:flutter_mcp_toolkit_release_flutter/flutter_mcp_toolkit_release_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const _otp = '123456';

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: Column(
          children: <Widget>[
            ElevatedButton(onPressed: () {}, child: const Text('Pay now')),
            const TextField(
              key: Key('note'),
              decoration: InputDecoration(labelText: 'Note'),
            ),
            TextField(
              key: const Key('otp'),
              obscureText: true,
              decoration: const InputDecoration(labelText: 'One-time code'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('otp')), _otp);
  await tester.pumpAndSettle();
}

/// Runs [body] with semantics enabled and disposes the handle before the test
/// binding's end-of-test audit (a tearDown is too late for that check).
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

/// Captures without deadlocking the test binding: the snapshot walk schedules a
/// frame and awaits it, so the frame has to be pumped while the capture is in
/// flight.
Future<T> _whilePumping<T>(WidgetTester tester, Future<T> pending) async {
  await tester.pump();
  await tester.pump();
  return pending;
}

void main() {
  testWidgets('captures the tree with refs, labels, and a numeric id', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await _pumpApp(tester);

      final source = FlutterReleaseUiSnapshotSource();
      final snapshot = await _whilePumping(tester, source.captureSnapshot());

      expect(snapshot.nodes, isNotEmpty);
      expect(int.tryParse(snapshot.snapshotId), isNotNull);

      final labels = snapshot.nodes
          .map((node) => node.label)
          .whereType<String>();
      expect(labels, contains('Pay now'));
      expect(labels.any((label) => label.contains('Checkout')), isTrue);

      final refs = snapshot.nodes.map((node) => node.ref).toList();
      expect(refs.toSet().length, refs.length, reason: 'refs must be unique');
      expect(
        snapshot.nodes.where((node) => node.actions.contains('tap')).length,
        greaterThan(0),
      );
    });
  });

  testWidgets('marks the obscured field sensitive and never ships its value', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await _pumpApp(tester);

      final source = FlutterReleaseUiSnapshotSource();
      final snapshot = await _whilePumping(tester, source.captureSnapshot());

      expect(
        snapshot.nodes.where((node) => node.sensitive),
        isNotEmpty,
        reason: 'the OTP field is obscured',
      );

      // The adapter marks the node; the runtime's filter is what removes text.
      final tools = ReleaseReadTools(source: source);
      final result = await _whilePumping(
        tester,
        tools.call('ui_get_tree', <String, Object?>{}),
      );

      expect(result.success, isTrue);
      expect(result.data.toString(), isNot(contains(_otp)));
      final nodes = (result.data!['nodes']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(nodes.where((node) => node['value'] == '••••'), isNotEmpty);
    });
  });

  testWidgets('finds a button by label through the read tools', (tester) async {
    await _withSemantics(tester, () async {
      await _pumpApp(tester);

      final tools = ReleaseReadTools(source: FlutterReleaseUiSnapshotSource());
      final result = await _whilePumping(
        tester,
        tools.call('ui_find_element', <String, Object?>{'label': 'Pay now'}),
      );

      expect(result.success, isTrue);
      final node = result.data!['node']! as Map<String, Object?>;
      expect(node['actions'], contains('tap'));
    });
  });

  testWidgets('reports the route the provider supplies', (tester) async {
    await _withSemantics(tester, () async {
      await _pumpApp(tester);

      final source = FlutterReleaseUiSnapshotSource(
        routeProvider: CallbackReleaseRouteProvider(() async => '/checkout'),
      );
      final snapshot = await _whilePumping(tester, source.captureSnapshot());

      expect(snapshot.routeName, '/checkout');
    });
  });

  testWidgets(
    'AgentSensitive masks its subtree and ExcludeFromAgent hides it',
    (tester) async {
      await _withSemantics(tester, () async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  AgentSensitive(
                    child: Text('Card number 4111 1111 1111 1111'),
                  ),
                  ExcludeFromAgent(child: Text('internal note 999')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final tools = ReleaseReadTools(
          source: FlutterReleaseUiSnapshotSource(),
        );
        final result = await _whilePumping(
          tester,
          tools.call('ui_get_tree', <String, Object?>{}),
        );

        expect(result.success, isTrue);
        final payload = result.toJson().toString();
        expect(payload, isNot(contains('4111')));
        expect(payload, isNot(contains('internal note')));
      });
    },
  );

  testWidgets('readCurrentPage does not advance the snapshot id', (
    tester,
  ) async {
    await _withSemantics(tester, () async {
      await _pumpApp(tester);

      final source = FlutterReleaseUiSnapshotSource();
      final first = await _whilePumping(tester, source.captureSnapshot());
      final page = await _whilePumping(tester, source.readCurrentPage());

      expect(page.snapshotId, first.snapshotId);
      expect(page.nodeCount, greaterThan(0));
      expect(page.interactionSurface, isNotNull);
    });
  });
}
