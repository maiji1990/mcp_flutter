// packages/release_runtime/lib/src/tools/capture_tools.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'dart:convert';

import '../capture/capture_policy.dart';
import '../capture/capture_source.dart';
import '../errors/release_mcp_error.dart';
import '../security/permissions.dart';
import 'release_tools.dart';

/// `ui_capture`: one screenshot, behind `ui:capture` and a route policy.
///
/// Three refusals guard the pixels: the permission (nothing captures without
/// explicit consent), the route policy (a blocked route is refused *before* the
/// frame is taken), and the byte budget (a full-resolution PNG of a phone screen
/// can be several megabytes, and the answer is base64 in a JSON envelope).
final class ReleaseCaptureTools implements ReleaseToolSurface {
  ReleaseCaptureTools({
    required this.source,
    this.policy = const ReleaseCapturePolicy(),
    this.maxBytes = 1536 * 1024,
    this.minScale = 0.1,
    this.maxScale = 3,
  });

  /// Where frames come from (the Flutter adapter in a release app).
  final ReleaseUiCaptureSource source;

  /// Which routes may be captured.
  final ReleaseCapturePolicy policy;

  /// Largest encoded image accepted; bigger answers are refused, not truncated.
  final int maxBytes;

  /// Smallest accepted [ReleaseCaptureRequest.scale].
  final double minScale;

  /// Largest accepted [ReleaseCaptureRequest.scale].
  final double maxScale;

  int _requests = 0;

  @override
  List<ReleaseToolDefinition> get tools => <ReleaseToolDefinition>[
    ReleaseToolDefinition(
      name: 'ui_capture',
      description:
          'Capture the current screen as PNG, subject to the app route policy. '
          'Requires ui:capture.',
      inputSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'scale': <String, Object?>{
            'type': 'number',
            'minimum': minScale,
            'maximum': maxScale,
            'description': 'Resolution multiplier, default 1.0.',
          },
          'format': <String, Object?>{
            'type': 'string',
            'enum': <String>['png'],
            'description': 'Only PNG is available in v1.',
          },
        },
        'additionalProperties': false,
      },
      permission: ReleasePermissionId.uiCapture,
    ),
  ];

  @override
  Future<ReleaseToolCallResult> call(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final requestId = 'req_${++_requests}';
    if (name != 'ui_capture') {
      return _refusal(
        requestId,
        ReleaseMcpErrorCode.toolNotFound,
        'Call tools/list for the catalog.',
      );
    }

    final rawScale = arguments['scale'];
    var scale = 1.0;
    if (rawScale != null) {
      if (rawScale is! num || rawScale < minScale || rawScale > maxScale) {
        return _refusal(
          requestId,
          ReleaseMcpErrorCode.invalidArgument,
          'scale must be between $minScale and $maxScale.',
        );
      }
      scale = rawScale.toDouble();
    }

    final rawFormat = arguments['format'];
    final ReleaseCaptureFormat format;
    if (rawFormat == null) {
      format = ReleaseCaptureFormat.png;
    } else if (rawFormat is! String) {
      return _refusal(
        requestId,
        ReleaseMcpErrorCode.invalidArgument,
        'format must be a string.',
      );
    } else {
      final parsed = ReleaseCaptureFormat.tryParse(rawFormat);
      if (parsed == null) {
        return _refusal(
          requestId,
          ReleaseMcpErrorCode.invalidArgument,
          'format must be one of png.',
        );
      }
      if (parsed != ReleaseCaptureFormat.png) {
        return _refusal(
          requestId,
          ReleaseMcpErrorCode.unsupportedFormat,
          'Only PNG is available in this version.',
        );
      }
      format = parsed;
    }

    final String? route;
    try {
      route = await source.currentRouteName();
    } catch (error) {
      return _refusal(
        requestId,
        ReleaseMcpErrorCode.captureUnavailable,
        'The app could not report its route, so capture was not attempted.',
        details: <String, Object?>{'cause': error.runtimeType.toString()},
      );
    }
    if (!policy.allows(route)) {
      return _refusal(
        requestId,
        ReleaseMcpErrorCode.routeBlocked,
        'Capture is not allowed on this screen.',
        details: <String, Object?>{
          'routeKnown': route != null && route.trim().isNotEmpty,
        },
      );
    }

    final ReleaseCaptureResult? capture;
    try {
      capture = await source.capture(
        ReleaseCaptureRequest(scale: scale, format: format),
      );
    } catch (error) {
      return _refusal(
        requestId,
        ReleaseMcpErrorCode.captureUnavailable,
        'The capture failed.',
        details: <String, Object?>{'cause': error.runtimeType.toString()},
      );
    }
    if (capture == null) {
      return _refusal(
        requestId,
        ReleaseMcpErrorCode.captureUnavailable,
        'Nothing could be captured right now.',
      );
    }

    if (capture.byteLength > maxBytes) {
      return _refusal(
        requestId,
        ReleaseMcpErrorCode.captureTooLarge,
        'Ask for a smaller scale.',
        details: <String, Object?>{
          'byteLength': capture.byteLength,
          'maxBytes': maxBytes,
          'width': capture.width,
          'height': capture.height,
        },
      );
    }

    return ReleaseToolCallResult(
      requestId: requestId,
      success: true,
      data: <String, Object?>{
        'mimeType': capture.mimeType,
        'width': capture.width,
        'height': capture.height,
        'byteLength': capture.byteLength,
        'scale': scale,
        'bytesBase64': base64Encode(capture.bytes),
      },
    );
  }

  ReleaseToolCallResult _refusal(
    String requestId,
    String code,
    String hint, {
    Map<String, Object?> details = const <String, Object?>{},
  }) => ReleaseToolCallResult(
    requestId: requestId,
    success: false,
    error: ReleaseToolError(
      code,
      '${descriptorForReleaseErrorCode(code).message} $hint',
      details: details,
    ),
  );
}
