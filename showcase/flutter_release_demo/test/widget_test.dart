// showcase/flutter_release_demo/test/widget_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fixture smoke test: the demo screen renders its controls. The runtime itself
// is exercised by the widget tests in packages/release_runtime_flutter and, on
// a device, by tool/mcp_smoke.dart.

import 'package:flutter/material.dart';
import 'package:flutter_release_demo/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the consent switch and the demo widgets', (
    tester,
  ) async {
    await tester.pumpWidget(const ReleaseDemoApp());
    await tester.pumpAndSettle();

    expect(find.text('Allow local AI access'), findsOneWidget);
    expect(find.text('Increment'), findsOneWidget);
    expect(find.text('Counter: 0'), findsOneWidget);
    expect(find.text('Open secret screen'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Increment'));
    await tester.pumpAndSettle();
    expect(find.text('Counter: 1'), findsOneWidget);
  });
}
