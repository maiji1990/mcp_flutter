// packages/release_runtime/lib/src/capture/capture_source.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Encoding of a capture.
enum ReleaseCaptureFormat {
  png('png'),
  jpeg('jpeg');

  const ReleaseCaptureFormat(this.wireName);

  final String wireName;

  /// Parses a wire value, or null when it is not a format.
  static ReleaseCaptureFormat? tryParse(String value) {
    final normalized = value.trim().toLowerCase();
    for (final format in ReleaseCaptureFormat.values) {
      if (format.wireName == normalized) {
        return format;
      }
    }
    return null;
  }
}

/// What to capture.
@immutable
final class ReleaseCaptureRequest {
  const ReleaseCaptureRequest({required this.scale, required this.format});

  /// Resolution multiplier: 1.0 is the device pixel ratio, 0.5 is half of it.
  final double scale;

  /// Requested encoding.
  final ReleaseCaptureFormat format;
}

/// A captured frame.
@immutable
final class ReleaseCaptureResult {
  const ReleaseCaptureResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.mimeType,
  });

  /// Encoded image bytes.
  final Uint8List bytes;

  /// Pixel width of [bytes].
  final int width;

  /// Pixel height of [bytes].
  final int height;

  /// MIME type of [bytes], for example `image/png`.
  final String mimeType;

  int get byteLength => bytes.length;
}

/// The pixel side of the release runtime.
///
/// Capture is the one tool whose output cannot be made safe by redaction: a
/// pixel dump shows whatever was on screen. That is why the runtime refuses
/// blocked routes *before* calling this, and why implementations must return
/// null rather than a best-effort image when they cannot honour the request
/// (protected content, no painted layer).
abstract interface class ReleaseUiCaptureSource {
  /// Route the app is showing, so the runtime can apply its capture policy.
  Future<String?> currentRouteName();

  /// Captures a frame, or returns null when capture is not possible.
  Future<ReleaseCaptureResult?> capture(ReleaseCaptureRequest request);
}
