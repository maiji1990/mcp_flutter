// packages/release_runtime/lib/src/tools/toolbox.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import '../security/call_authorization.dart';
import 'release_tools.dart';

/// One surface over several, so a runtime can expose read and interaction
/// tools together without knowing either.
///
/// Names must be unique across the parts; a duplicate throws at construction
/// instead of silently shadowing one implementation with another.
final class ReleaseToolbox implements ReleaseToolSurface {
  ReleaseToolbox(Iterable<ReleaseToolSurface> parts)
    : parts = List<ReleaseToolSurface>.unmodifiable(parts) {
    final seen = <String>{};
    for (final part in this.parts) {
      for (final tool in part.tools) {
        if (!seen.add(tool.name)) {
          throw ArgumentError.value(
            tool.name,
            'parts',
            'Duplicate tool name across surfaces',
          );
        }
      }
    }
  }

  /// The surfaces this box fronts, in call order.
  final List<ReleaseToolSurface> parts;

  @override
  List<ReleaseToolDefinition> get tools => <ReleaseToolDefinition>[
    for (final part in parts) ...part.tools,
  ];

  @override
  Future<ReleaseToolCallResult> call(
    String name,
    Map<String, Object?> arguments, {
    ReleaseCallAuthorization? authorization,
  }) {
    for (final part in parts) {
      for (final tool in part.tools) {
        if (tool.name == name) {
          return part.call(name, arguments, authorization: authorization);
        }
      }
    }
    return Future<ReleaseToolCallResult>.value(
      ReleaseToolCallResult(
        requestId: 'req_unknown',
        success: false,
        error: const ReleaseToolError(
          'tool_not_found',
          'That tool is not available in this session.',
        ),
      ),
    );
  }
}
