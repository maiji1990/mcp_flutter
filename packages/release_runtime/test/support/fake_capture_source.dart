// packages/release_runtime/test/support/fake_capture_source.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';

/// Capture source that records requests and returns a fixed frame.
final class FakeCaptureSource implements ReleaseUiCaptureSource {
  FakeCaptureSource({
    this.routeName,
    Uint8List? bytes,
    this.width = 1080,
    this.height = 2400,
    this.nullResult = false,
    this.routeThrows = false,
    this.captureThrows = false,
  }) : bytes = bytes ?? Uint8List.fromList(List<int>.filled(32, 7));

  String? routeName;
  Uint8List bytes;
  int width;
  int height;
  bool nullResult;
  bool routeThrows;
  bool captureThrows;

  final List<ReleaseCaptureRequest> requests = <ReleaseCaptureRequest>[];

  @override
  Future<String?> currentRouteName() async {
    if (routeThrows) {
      throw StateError('router blew up');
    }
    return routeName;
  }

  @override
  Future<ReleaseCaptureResult?> capture(ReleaseCaptureRequest request) async {
    requests.add(request);
    if (captureThrows) {
      throw StateError('capture blew up');
    }
    if (nullResult) {
      return null;
    }
    return ReleaseCaptureResult(
      bytes: bytes,
      width: width,
      height: height,
      mimeType: 'image/png',
    );
  }
}
