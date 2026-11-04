// packages/release_runtime_flutter/test/flutter_capture_source_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:flutter_mcp_toolkit_release_flutter/flutter_mcp_toolkit_release_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const List<int> _pngSignature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

void main() {
  testWidgets('captures the screen as a PNG', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Captured'))),
      ),
    );
    await tester.pumpAndSettle();

    const source = FlutterReleaseUiCaptureSource();
    // Rasterising a scene is real engine work, not fake-async work, so it runs
    // inside runAsync: pumping only drives the Flutter side.
    final result = await tester.runAsync(
      () => source.capture(
        const ReleaseCaptureRequest(scale: 1, format: ReleaseCaptureFormat.png),
      ),
    );

    expect(result, isNotNull);
    expect(result!.mimeType, 'image/png');
    expect(result.bytes.sublist(0, 8), _pngSignature);
    expect(result.width, greaterThan(0));
    expect(result.height, greaterThan(0));
  });

  testWidgets('ui_capture returns base64 the client can decode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Captured'))),
      ),
    );
    await tester.pumpAndSettle();

    final tools = ReleaseCaptureTools(
      source: const FlutterReleaseUiCaptureSource(),
      maxBytes: 5 * 1024 * 1024,
    );

    final result = await tester.runAsync(
      () => tools.call('ui_capture', <String, Object?>{'scale': 0.5}),
    );
    expect(result, isNotNull);

    expect(result!.success, isTrue, reason: result.error?.message);
    final data = result.data!;
    expect(data['mimeType'], 'image/png');
    final bytes = base64Decode(data['bytesBase64']! as String);
    expect(bytes.sublist(0, 8), _pngSignature);
    expect((data['width']! as int), greaterThan(0));
  });

  testWidgets('a blocked route is refused before the frame is taken', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Secret'))),
      ),
    );
    await tester.pumpAndSettle();

    final tools = ReleaseCaptureTools(
      source: FlutterReleaseUiCaptureSource(
        routeProvider: CallbackReleaseRouteProvider(() async => '/wallet'),
      ),
      policy: const ReleaseCapturePolicy(blockedRoutes: <String>{'/wallet'}),
    );

    final result = await tools.call('ui_capture', <String, Object?>{});

    expect(result.success, isFalse);
    expect(result.error!.code, ReleaseMcpErrorCode.routeBlocked);
  });
}
