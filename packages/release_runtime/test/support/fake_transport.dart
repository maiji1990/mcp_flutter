// packages/release_runtime/test/support/fake_transport.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';

/// Recording transport used by the runtime tests.
final class FakeTransport implements ReleaseRuntimeTransport {
  FakeTransport({this.endpoint, this.startError, this.stopError});

  final Uri? endpoint;
  final Object? startError;
  final Object? stopError;

  int startCalls = 0;
  int stopCalls = 0;
  ReleaseTransportStartRequest? lastRequest;

  @override
  Future<Uri?> start(ReleaseTransportStartRequest request) async {
    startCalls += 1;
    lastRequest = request;
    final error = startError;
    if (error != null) {
      throw error;
    }
    return endpoint;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    final error = stopError;
    if (error != null) {
      throw error;
    }
  }
}
