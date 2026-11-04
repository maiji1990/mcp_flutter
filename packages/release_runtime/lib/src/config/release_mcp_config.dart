// packages/release_runtime/lib/src/config/release_mcp_config.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime). This file is not part of the
// upstream `mcp_toolkit` / `mcp_server_dart` packages.

import 'package:meta/meta.dart';

/// One field-scoped configuration problem.
///
/// Both members are stable, non-sensitive identifiers: [field] names the
/// offending knob, [code] names the rule that failed. Neither carries a value,
/// so problems are safe to log and safe to return to a client.
@immutable
final class ReleaseConfigProblem {
  const ReleaseConfigProblem(this.field, this.code);

  /// Name of the [ReleaseMcpConfig] field that failed validation.
  final String field;

  /// Stable problem code, for example `port_out_of_range`.
  final String code;

  Map<String, Object?> toJson() => <String, Object?>{
    'field': field,
    'code': code,
  };

  @override
  bool operator ==(Object other) =>
      other is ReleaseConfigProblem &&
      other.field == field &&
      other.code == code;

  @override
  int get hashCode => Object.hash(field, code);

  @override
  String toString() => '$field:$code';
}

/// Immutable configuration for [ReleaseMcpRuntime].
///
/// The defaults are the security defaults: loopback-only binding, read-only
/// session, no listener started on construction.
///
/// This type owns validation only. It never binds a socket, never reads
/// platform state, and never starts anything: constructing a config (or a
/// runtime) has no side effects.
@immutable
final class ReleaseMcpConfig {
  const ReleaseMcpConfig({
    this.host = loopbackIPv4,
    this.port = defaultPort,
    this.endpoint = defaultEndpoint,
    this.enabledOnStartup = false,
    this.readOnlyByDefault = true,
    this.allowNonLoopbackBinding = false,
    this.maxRequestBytes = defaultMaxRequestBytes,
    this.requestTimeout = defaultRequestTimeout,
    this.maxConcurrentRequests = defaultMaxConcurrentRequests,
    this.maxSessions = defaultMaxSessions,
    this.sessionIdleTimeout = defaultSessionIdleTimeout,
  });

  /// IPv4 loopback literal.
  static const String loopbackIPv4 = '127.0.0.1';

  /// IPv6 loopback literal.
  static const String loopbackIPv6 = '::1';

  /// Loopback host name.
  static const String loopbackHostname = 'localhost';

  /// Default MCP port, matching the plan's `127.0.0.1:8765` deployment.
  static const int defaultPort = 8765;

  /// Default MCP endpoint path.
  static const String defaultEndpoint = '/mcp';

  /// Default request body ceiling (1 MiB).
  static const int defaultMaxRequestBytes = 1024 * 1024;

  /// Default per-request timeout.
  static const Duration defaultRequestTimeout = Duration(seconds: 30);

  /// Default number of in-flight requests the transport may accept.
  static const int defaultMaxConcurrentRequests = 4;

  /// Default number of concurrent MCP sessions the server keeps.
  ///
  /// Sessions are cheap but not free: a client that never sends `DELETE` leaves
  /// one behind until it idles out. A small budget (the SDK default is 100) is
  /// not the point here — the point is that a handful of test runs must not
  /// exhaust it.
  static const int defaultMaxSessions = 32;

  /// Default idle time after which an unused session is freed.
  static const Duration defaultSessionIdleTimeout = Duration(minutes: 10);

  /// Lowest accepted port. `0` asks the OS for an ephemeral port.
  static const int minPort = 0;

  /// Highest accepted port.
  static const int maxPort = 65535;

  /// Smallest accepted request body ceiling.
  static const int minRequestBytes = 1024;

  /// Hard ceiling for request bodies (8 MiB).
  static const int maxRequestBytesCeiling = 8 * 1024 * 1024;

  /// Hard ceiling for the per-request timeout.
  static const Duration maxRequestTimeout = Duration(minutes: 5);

  /// Hard ceiling for in-flight requests.
  static const int maxConcurrentRequestsCeiling = 64;

  /// Hard ceiling for sessions.
  static const int maxSessionsCeiling = 256;

  /// Shortest accepted session idle timeout.
  static const Duration minSessionIdleTimeout = Duration(seconds: 30);

  /// Longest accepted session idle timeout.
  static const Duration maxSessionIdleTimeout = Duration(hours: 24);

  /// Interface to bind. Only loopback is allowed unless
  /// [allowNonLoopbackBinding] is explicitly set.
  final String host;

  /// TCP port to bind. `0` means "let the OS pick an ephemeral port".
  final int port;

  /// HTTP path serving MCP. Must start with `/`.
  final String endpoint;

  /// Hint for the host app: it may start the runtime at launch. The runtime
  /// itself never starts a listener on construction or on import.
  final bool enabledOnStartup;

  /// When true, starting without an explicit authorization yields a read-only
  /// session. When false, starting without an explicit authorization is
  /// rejected instead of silently degrading.
  final bool readOnlyByDefault;

  /// Escape hatch for non-loopback binding. Defaults to false because the
  /// local loopback address is still reachable by other apps on the device.
  final bool allowNonLoopbackBinding;

  /// Maximum accepted request body size in bytes.
  final int maxRequestBytes;

  /// Per-request timeout enforced by the transport.
  final Duration requestTimeout;

  /// Maximum number of requests the transport serves concurrently.
  final int maxConcurrentRequests;

  /// Maximum number of MCP sessions the server keeps at once.
  final int maxSessions;

  /// Idle time after which an unused session is freed.
  final Duration sessionIdleTimeout;

  /// True when [host] is one of the three loopback spellings.
  bool get isLoopbackHost =>
      host == loopbackIPv4 || host == loopbackIPv6 || host == loopbackHostname;

  /// True when [validate] reports no problems.
  bool get isValid => validate().isEmpty;

  /// Returns every rule that [this] configuration violates.
  ///
  /// Validation is pure and idempotent, so callers may run it before showing
  /// consent UI and again when starting.
  List<ReleaseConfigProblem> validate() {
    final problems = <ReleaseConfigProblem>[];

    final trimmedHost = host.trim();
    // A bare host only: schemes, paths, and "host:port" spellings are rejected
    // here so a typo cannot silently become a different bind address. The only
    // accepted colon form is the IPv6 loopback literal; other IPv6 literals are
    // out of scope for V1.
    if (trimmedHost.isEmpty) {
      problems.add(const ReleaseConfigProblem('host', 'empty'));
    } else if (trimmedHost != host ||
        host.contains('/') ||
        host.contains(' ') ||
        host.contains('://') ||
        (host.contains(':') && host != loopbackIPv6)) {
      problems.add(const ReleaseConfigProblem('host', 'invalid_host'));
    } else if (!isLoopbackHost && !allowNonLoopbackBinding) {
      problems.add(
        const ReleaseConfigProblem('host', 'non_loopback_requires_opt_in'),
      );
    }

    if (port < minPort || port > maxPort) {
      problems.add(const ReleaseConfigProblem('port', 'port_out_of_range'));
    }

    if (endpoint.length < 2 ||
        !endpoint.startsWith('/') ||
        endpoint.contains('?') ||
        endpoint.contains('#') ||
        endpoint.contains(' ') ||
        endpoint.length > 128) {
      problems.add(const ReleaseConfigProblem('endpoint', 'invalid_endpoint'));
    }

    if (maxRequestBytes < minRequestBytes ||
        maxRequestBytes > maxRequestBytesCeiling) {
      problems.add(
        const ReleaseConfigProblem(
          'maxRequestBytes',
          'max_request_bytes_out_of_range',
        ),
      );
    }

    if (requestTimeout <= Duration.zero || requestTimeout > maxRequestTimeout) {
      problems.add(
        const ReleaseConfigProblem(
          'requestTimeout',
          'request_timeout_out_of_range',
        ),
      );
    }

    if (maxConcurrentRequests < 1 ||
        maxConcurrentRequests > maxConcurrentRequestsCeiling) {
      problems.add(
        const ReleaseConfigProblem(
          'maxConcurrentRequests',
          'max_concurrent_requests_out_of_range',
        ),
      );
    }

    if (maxSessions < 1 || maxSessions > maxSessionsCeiling) {
      problems.add(
        const ReleaseConfigProblem('maxSessions', 'max_sessions_out_of_range'),
      );
    }

    if (sessionIdleTimeout < minSessionIdleTimeout ||
        sessionIdleTimeout > maxSessionIdleTimeout) {
      problems.add(
        const ReleaseConfigProblem(
          'sessionIdleTimeout',
          'session_idle_timeout_out_of_range',
        ),
      );
    }

    return List<ReleaseConfigProblem>.unmodifiable(problems);
  }

  ReleaseMcpConfig copyWith({
    String? host,
    int? port,
    String? endpoint,
    bool? enabledOnStartup,
    bool? readOnlyByDefault,
    bool? allowNonLoopbackBinding,
    int? maxRequestBytes,
    Duration? requestTimeout,
    int? maxConcurrentRequests,
    int? maxSessions,
    Duration? sessionIdleTimeout,
  }) => ReleaseMcpConfig(
    host: host ?? this.host,
    port: port ?? this.port,
    endpoint: endpoint ?? this.endpoint,
    enabledOnStartup: enabledOnStartup ?? this.enabledOnStartup,
    readOnlyByDefault: readOnlyByDefault ?? this.readOnlyByDefault,
    allowNonLoopbackBinding:
        allowNonLoopbackBinding ?? this.allowNonLoopbackBinding,
    maxRequestBytes: maxRequestBytes ?? this.maxRequestBytes,
    requestTimeout: requestTimeout ?? this.requestTimeout,
    maxConcurrentRequests: maxConcurrentRequests ?? this.maxConcurrentRequests,
    maxSessions: maxSessions ?? this.maxSessions,
    sessionIdleTimeout: sessionIdleTimeout ?? this.sessionIdleTimeout,
  );

  /// Redaction-safe JSON view. Contains no token, no secret, no user data.
  Map<String, Object?> toJson() => <String, Object?>{
    'host': host,
    'port': port,
    'endpoint': endpoint,
    'enabledOnStartup': enabledOnStartup,
    'readOnlyByDefault': readOnlyByDefault,
    'allowNonLoopbackBinding': allowNonLoopbackBinding,
    'maxRequestBytes': maxRequestBytes,
    'requestTimeoutMs': requestTimeout.inMilliseconds,
    'maxConcurrentRequests': maxConcurrentRequests,
    'maxSessions': maxSessions,
    'sessionIdleTimeoutMs': sessionIdleTimeout.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is ReleaseMcpConfig &&
      other.host == host &&
      other.port == port &&
      other.endpoint == endpoint &&
      other.enabledOnStartup == enabledOnStartup &&
      other.readOnlyByDefault == readOnlyByDefault &&
      other.allowNonLoopbackBinding == allowNonLoopbackBinding &&
      other.maxRequestBytes == maxRequestBytes &&
      other.requestTimeout == requestTimeout &&
      other.maxConcurrentRequests == maxConcurrentRequests &&
      other.maxSessions == maxSessions &&
      other.sessionIdleTimeout == sessionIdleTimeout;

  @override
  int get hashCode => Object.hash(
    host,
    port,
    endpoint,
    enabledOnStartup,
    readOnlyByDefault,
    allowNonLoopbackBinding,
    maxRequestBytes,
    requestTimeout,
    maxConcurrentRequests,
    maxSessions,
    sessionIdleTimeout,
  );

  @override
  String toString() =>
      'ReleaseMcpConfig(host: $host, port: $port, endpoint: $endpoint, '
      'readOnlyByDefault: $readOnlyByDefault)';
}
