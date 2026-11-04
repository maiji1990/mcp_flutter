// packages/release_runtime/test/config/release_mcp_config_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseMcpConfig defaults', () {
    test('are loopback, read-only, and off by default', () {
      const config = ReleaseMcpConfig();

      expect(config.host, ReleaseMcpConfig.loopbackIPv4);
      expect(config.port, ReleaseMcpConfig.defaultPort);
      expect(config.endpoint, ReleaseMcpConfig.defaultEndpoint);
      expect(config.enabledOnStartup, isFalse);
      expect(config.readOnlyByDefault, isTrue);
      expect(config.allowNonLoopbackBinding, isFalse);
      expect(config.isLoopbackHost, isTrue);
      expect(config.validate(), isEmpty);
      expect(config.isValid, isTrue);
      expect(config.port, 8765);
    });

    test('toJson carries no secret material and stays stable', () {
      const config = ReleaseMcpConfig();
      final json = config.toJson();

      expect(
        json.keys,
        containsAll(<String>[
          'host',
          'port',
          'endpoint',
          'enabledOnStartup',
          'readOnlyByDefault',
          'allowNonLoopbackBinding',
          'maxRequestBytes',
          'requestTimeoutMs',
          'maxConcurrentRequests',
        ]),
      );
      expect(json['requestTimeoutMs'], 30000);
      expect(json.containsKey('token'), isFalse);
      expect(json.containsKey('authorization'), isFalse);
    });
  });

  group('ReleaseMcpConfig host rules', () {
    test('rejects empty and malformed hosts', () {
      expect(
        const ReleaseMcpConfig(host: '  ').validate().single,
        const ReleaseConfigProblem('host', 'empty'),
      );
      expect(
        const ReleaseMcpConfig(host: 'http://127.0.0.1').validate().single,
        const ReleaseConfigProblem('host', 'invalid_host'),
      );
      expect(
        const ReleaseMcpConfig(host: '127.0.0.1:8765').validate().single,
        const ReleaseConfigProblem('host', 'invalid_host'),
      );
    });

    test('rejects non-loopback binding without the explicit opt-in', () {
      final problems = const ReleaseMcpConfig(host: '0.0.0.0').validate();

      expect(problems, hasLength(1));
      expect(problems.single.field, 'host');
      expect(problems.single.code, 'non_loopback_requires_opt_in');
    });

    test('allows non-loopback binding once opted in', () {
      const config = ReleaseMcpConfig(
        host: '0.0.0.0',
        allowNonLoopbackBinding: true,
      );

      expect(config.validate(), isEmpty);
      expect(config.isLoopbackHost, isFalse);
    });

    test('accepts every loopback spelling', () {
      for (final host in <String>['127.0.0.1', '::1', 'localhost']) {
        expect(ReleaseMcpConfig(host: host).validate(), isEmpty, reason: host);
      }
    });
  });

  group('ReleaseMcpConfig budgets', () {
    test('port must be 0..65535, with 0 meaning "ephemeral"', () {
      expect(
        const ReleaseMcpConfig(port: -1).validate().single,
        const ReleaseConfigProblem('port', 'port_out_of_range'),
      );
      expect(
        const ReleaseMcpConfig(port: 65536).validate().single,
        const ReleaseConfigProblem('port', 'port_out_of_range'),
      );
      expect(const ReleaseMcpConfig(port: 0).validate(), isEmpty);
      expect(const ReleaseMcpConfig(port: 65535).validate(), isEmpty);
    });

    test('endpoint must be an absolute path without query or fragment', () {
      for (final endpoint in <String>['mcp', '/mcp?x=1', '/mcp#frag', '/']) {
        final problems = ReleaseMcpConfig(endpoint: endpoint).validate();
        expect(problems, hasLength(1), reason: endpoint);
        expect(problems.single.field, 'endpoint', reason: endpoint);
        expect(problems.single.code, 'invalid_endpoint', reason: endpoint);
      }
      expect(
        const ReleaseMcpConfig(endpoint: '/release/mcp').validate(),
        isEmpty,
      );
    });

    test('request budget and concurrency stay inside their ceilings', () {
      expect(
        const ReleaseMcpConfig(maxRequestBytes: 1).validate().single.code,
        'max_request_bytes_out_of_range',
      );
      expect(
        const ReleaseMcpConfig(
          maxRequestBytes: ReleaseMcpConfig.maxRequestBytesCeiling + 1,
        ).validate().single.code,
        'max_request_bytes_out_of_range',
      );
      expect(
        const ReleaseMcpConfig(requestTimeout: Duration.zero)
            .validate()
            .single
            .code,
        'request_timeout_out_of_range',
      );
      expect(
        const ReleaseMcpConfig(maxConcurrentRequests: 0).validate().single.code,
        'max_concurrent_requests_out_of_range',
      );
      expect(
        const ReleaseMcpConfig(
          maxConcurrentRequests:
              ReleaseMcpConfig.maxConcurrentRequestsCeiling + 1,
        ).validate().single.code,
        'max_concurrent_requests_out_of_range',
      );
    });

    test('reports every violation at once, in a stable order', () {
      const config = ReleaseMcpConfig(
        host: '0.0.0.0',
        port: 99999,
        endpoint: 'mcp',
      );

      expect(
        config.validate().map((problem) => '${problem.field}/${problem.code}'),
        <String>[
          'host/non_loopback_requires_opt_in',
          'port/port_out_of_range',
          'endpoint/invalid_endpoint',
        ],
      );
    });
  });

  group('ReleaseMcpConfig value semantics', () {
    test('copyWith changes only the requested fields', () {
      const config = ReleaseMcpConfig();
      final updated = config.copyWith(port: 9000, readOnlyByDefault: false);

      expect(updated.port, 9000);
      expect(updated.readOnlyByDefault, isFalse);
      expect(updated.host, config.host);
      expect(updated.endpoint, config.endpoint);
      expect(updated, isNot(config));
    });

    test('equality is structural', () {
      expect(const ReleaseMcpConfig(), const ReleaseMcpConfig());
      expect(
        const ReleaseMcpConfig().hashCode,
        const ReleaseMcpConfig().hashCode,
      );
    });
  });
}
