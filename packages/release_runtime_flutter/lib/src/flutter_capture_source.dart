// packages/release_runtime_flutter/lib/src/flutter_capture_source.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
// The toolkit's barrel does not export ScreenshotService yet, and the fork does
// not modify upstream public surfaces (PR-01 rule). A deep import keeps the
// single implementation of "render the RenderView to PNG" rather than writing a
// second one; if upstream exports it, switch to the barrel.
// ignore: implementation_imports
import 'package:mcp_toolkit/src/services/screenshot_service.dart'
    show ScreenshotService;

/// [ReleaseUiCaptureSource] backed by the toolkit's screenshot service.
///
/// Reuse: `ScreenshotService.takeScreenshots` already renders the RenderView
/// layer tree to a PNG and returns base64, including the "needs a frame first"
/// retry. This adapter adds what the runtime needs — a decoded frame it can
/// measure and resample to the requested scale — and nothing else.
///
/// Capture is the one tool whose output cannot be redacted after the fact, so
/// the route is reported here and the policy decision stays in the runtime: the
/// adapter never decides whether a screen may be captured.
final class FlutterReleaseUiCaptureSource implements ReleaseUiCaptureSource {
  const FlutterReleaseUiCaptureSource({this.routeProvider});

  /// Supplies the route name the runtime's capture policy checks.
  final ReleaseRouteProvider? routeProvider;

  @override
  Future<String?> currentRouteName() async {
    final provider = routeProvider;
    if (provider == null) {
      return null;
    }
    try {
      return await provider.currentRouteName();
    } on Object {
      // A router that throws must not turn into "no policy applies".
      return null;
    }
  }

  @override
  Future<ReleaseCaptureResult?> capture(ReleaseCaptureRequest request) async {
    final shots = await ScreenshotService.takeScreenshots(compress: false);
    if (shots.isEmpty) {
      return null;
    }

    final decodedBytes = base64Decode(shots.first);
    final decoded = await _decode(decodedBytes);
    if (decoded == null) {
      return null;
    }

    ui.Image? scaled;
    try {
      final image = request.scale == 1.0
          ? decoded
          : (scaled = await _resample(decoded, request.scale));
      final png = await _encodePng(image);
      return ReleaseCaptureResult(
        bytes: png,
        width: image.width,
        height: image.height,
        mimeType: 'image/png',
      );
    } finally {
      scaled?.dispose();
      decoded.dispose();
    }
  }

  static Future<ui.Image?> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } on Object {
      return null;
    }
  }

  static Future<ui.Image> _resample(ui.Image source, double scale) async {
    final width = (source.width * scale).round().clamp(1, 8192);
    final height = (source.height * scale).round().clamp(1, 8192);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  static Future<Uint8List> _encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('PNG encoding failed');
    }
    return data.buffer.asUint8List();
  }
}
