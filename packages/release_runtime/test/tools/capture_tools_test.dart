// packages/release_runtime/test/tools/capture_tools_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

import '../support/fake_capture_source.dart';

void main() {
  group('ui_capture', () {
    test('captures a frame and returns it base64 encoded', () async {
      final source = FakeCaptureSource(routeName: '/home');
      final tools = ReleaseCaptureTools(source: source);

      final result = await tools.call('ui_capture', <String, Object?>{});

      expect(result.success, isTrue, reason: result.error?.message);
      final data = result.data!;
      expect(data['mimeType'], 'image/png');
      expect(data['width'], 1080);
      expect(data['height'], 2400);
      expect(data['scale'], 1.0);
      expect(base64Decode(data['bytesBase64']! as String), source.bytes);
      expect(source.requests.single.scale, 1.0);
      expect(source.requests.single.format, ReleaseCaptureFormat.png);
    });

    test('passes the requested scale through', () async {
      final source = FakeCaptureSource();
      final tools = ReleaseCaptureTools(source: source);

      final result = await tools.call('ui_capture', <String, Object?>{
        'scale': 0.5,
      });

      expect(result.success, isTrue);
      expect(source.requests.single.scale, 0.5);
      expect(result.data!['scale'], 0.5);
    });

    test('a blocked route is refused before any capture', () async {
      final source = FakeCaptureSource(routeName: '/wallet');
      final tools = ReleaseCaptureTools(
        source: source,
        policy: const ReleaseCapturePolicy(blockedRoutes: <String>{'/wallet'}),
      );

      final result = await tools.call('ui_capture', <String, Object?>{});

      expect(result.success, isFalse);
      expect(result.error!.code, ReleaseMcpErrorCode.routeBlocked);
      expect(result.error!.details['routeKnown'], isTrue);
      expect(source.requests, isEmpty);
      expect(result.toJson().toString(), isNot(contains('/wallet')));
    });

    test('an unknown route can be refused by policy', () async {
      final source = FakeCaptureSource(routeName: null);
      final tools = ReleaseCaptureTools(
        source: source,
        policy: const ReleaseCapturePolicy(allowWhenRouteUnknown: false),
      );

      final result = await tools.call('ui_capture', <String, Object?>{});

      expect(result.error!.code, ReleaseMcpErrorCode.routeBlocked);
      expect(source.requests, isEmpty);
    });

    test('refuses an oversized frame instead of truncating it', () async {
      final source = FakeCaptureSource(
        bytes: Uint8List.fromList(List<int>.filled(64, 1)),
      );
      final tools = ReleaseCaptureTools(source: source, maxBytes: 32);

      final result = await tools.call('ui_capture', <String, Object?>{});

      expect(result.success, isFalse);
      expect(result.error!.code, ReleaseMcpErrorCode.captureTooLarge);
      expect(result.error!.details['byteLength'], 64);
      expect(result.error!.details['maxBytes'], 32);
      expect(result.data, isNull);
    });

    test('an unavailable capture is a refusal, not an empty image', () async {
      final source = FakeCaptureSource(nullResult: true);
      final tools = ReleaseCaptureTools(source: source);

      final result = await tools.call('ui_capture', <String, Object?>{});

      expect(result.error!.code, ReleaseMcpErrorCode.captureUnavailable);
    });

    test('a throwing source is reported without its message', () async {
      final source = FakeCaptureSource(captureThrows: true);
      final tools = ReleaseCaptureTools(source: source);

      final result = await tools.call('ui_capture', <String, Object?>{});

      expect(result.error!.code, ReleaseMcpErrorCode.captureUnavailable);
      expect(result.error!.details['cause'], 'StateError');
      expect(result.error!.message, isNot(contains('blew up')));
    });

    test('validates scale and format before touching the UI', () async {
      final source = FakeCaptureSource();
      final tools = ReleaseCaptureTools(source: source);

      final badScale = await tools.call('ui_capture', <String, Object?>{
        'scale': 9,
      });
      final badFormat = await tools.call('ui_capture', <String, Object?>{
        'format': 'webp',
      });
      final jpeg = await tools.call('ui_capture', <String, Object?>{
        'format': 'jpeg',
      });

      expect(badScale.error!.code, ReleaseMcpErrorCode.invalidArgument);
      expect(badFormat.error!.code, ReleaseMcpErrorCode.invalidArgument);
      expect(jpeg.error!.code, ReleaseMcpErrorCode.unsupportedFormat);
      expect(source.requests, isEmpty);
    });

    test('declares ui:capture as its permission', () {
      final tools = ReleaseCaptureTools(source: FakeCaptureSource());

      expect(tools.tools.single.name, 'ui_capture');
      expect(tools.tools.single.permission, ReleasePermissionId.uiCapture);
    });
  });
}
