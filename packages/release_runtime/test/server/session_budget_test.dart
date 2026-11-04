// packages/release_runtime/test/server/session_budget_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

import '../support/fake_snapshot_source.dart';
import '../support/mcp_http_client.dart';

void main() {
  test('a handful of clients can hold sessions at once', () async {
    final runtime = ReleaseMcpRuntime.http(
      config: const ReleaseMcpConfig(port: 0),
      tools: ReleaseReadTools(source: FakeSnapshotSource()),
    );
    addTearDown(runtime.dispose);
    final status = await runtime.start();

    // Regression: sessions used to be capped by maxConcurrentRequests (4), so a
    // few client runs locked out the next one with "Too many sessions".
    for (var index = 0; index < 6; index++) {
      final client = McpTestClient(status.endpoint!, runtime.accessToken.value);
      final result = await client.initialize();
      expect(result, isNotNull, reason: 'session $index must be accepted');
    }
  });

  test('maxSessions is configurable and validated', () async {
    expect(const ReleaseMcpConfig().maxSessions, 32);
    expect(
      const ReleaseMcpConfig().sessionIdleTimeout,
      const Duration(minutes: 10),
    );

    expect(
      const ReleaseMcpConfig(maxSessions: 0).validate().single,
      const ReleaseConfigProblem('maxSessions', 'max_sessions_out_of_range'),
    );
    expect(
      const ReleaseMcpConfig(maxSessions: 1000).validate().single,
      const ReleaseConfigProblem('maxSessions', 'max_sessions_out_of_range'),
    );
    expect(
      const ReleaseMcpConfig(sessionIdleTimeout: Duration(seconds: 1))
          .validate()
          .single,
      const ReleaseConfigProblem(
        'sessionIdleTimeout',
        'session_idle_timeout_out_of_range',
      ),
    );

    const configured = ReleaseMcpConfig(maxSessions: 8);
    expect(configured.validate(), isEmpty);
  });
}
