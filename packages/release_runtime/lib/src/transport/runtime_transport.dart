// packages/release_runtime/lib/src/transport/runtime_transport.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

import '../tools/release_tools.dart';

/// Everything a transport needs to bind.
///
/// This is a plain value object so a transport implementation can stay in its
/// own layer without importing runtime internals.
@immutable
final class ReleaseTransportStartRequest {
  const ReleaseTransportStartRequest({
    required this.host,
    required this.port,
    required this.endpoint,
    required this.requestTimeout,
    required this.maxRequestBytes,
    required this.maxConcurrentRequests,
    required this.maxSessions,
    required this.sessionIdleTimeout,
    required this.accessToken,
    this.toolSurface,
  });

  /// Interface to bind.
  final String host;

  /// Port to bind; `0` asks the OS for an ephemeral port.
  final int port;

  /// Path serving MCP.
  final String endpoint;

  /// Per-request timeout the transport must enforce.
  final Duration requestTimeout;

  /// Request body ceiling in bytes.
  final int maxRequestBytes;

  /// In-flight request ceiling.
  final int maxConcurrentRequests;

  /// Maximum number of concurrent MCP sessions the server keeps.
  final int maxSessions;

  /// Idle time after which an unused session is freed, so a client that never
  /// sends `DELETE` cannot exhaust [maxSessions].
  final Duration sessionIdleTimeout;

  /// Bearer secret every request must present.
  ///
  /// A transport must reject anything else before dispatch, must compare in
  /// constant time, and must never write this value to a log or echo it in a
  /// response.
  final String accessToken;

  /// Tools the transport should register, or null for a tool-less endpoint.
  ///
  /// The runtime hands over a permission-checked wrapper, so a transport never
  /// decides access; it only forwards calls.
  final ReleaseToolSurface? toolSurface;

  /// Same fields as [toJson], but with the secret redacted — safe to log.
  Map<String, Object?> toJson() => <String, Object?>{
    'host': host,
    'port': port,
    'endpoint': endpoint,
    'requestTimeoutMs': requestTimeout.inMilliseconds,
    'maxRequestBytes': maxRequestBytes,
    'maxConcurrentRequests': maxConcurrentRequests,
    'maxSessions': maxSessions,
    'sessionIdleTimeoutMs': sessionIdleTimeout.inMilliseconds,
    'accessToken': '<redacted>',
    'tools':
        toolSurface?.tools.map((tool) => tool.name).toList(growable: false) ??
        const <String>[],
  };
}

/// The seam between the runtime's lifecycle and an actual listener.
///
/// The runtime owns state, permissions, and (later) tools; a transport owns
/// sockets, request parsing, auth, and timeouts. Keeping them apart is what let
/// PR-01 ship without any socket code and lets the HTTP transport
/// ([HttpReleaseRuntimeTransport]) land as a drop-in.
///
/// Contract:
/// - [start] is called only from `ReleaseMcpRuntime.start()` after the
///   runtime moved to `starting`, and only when the runtime is `disabled` or
///   `error`.
/// - [start] returns the bound base URI, or `null` when the transport reserves
///   no endpoint (an inert transport). Throwing fails the start.
/// - [stop] is called at most once per successful [start], from `stop()` or
///   `dispose()`, and must release the socket before it returns.
/// - Implementations must never throw from a completed [stop]; the runtime
///   treats a throwing stop as `transport_stop_failed`.
abstract interface class ReleaseRuntimeTransport {
  /// Binds and begins serving.
  Future<Uri?> start(ReleaseTransportStartRequest request);

  /// Releases the listener. Must be safe to call after a failed [start].
  Future<void> stop();
}

/// Default transport: reserves no endpoint and always succeeds.
///
/// PR-01 ships this transport so the package can be wired into a release build
/// and unit-tested without exposing a network surface. The HTTP transport
/// arrives in PR-02.
final class InertRuntimeTransport implements ReleaseRuntimeTransport {
  const InertRuntimeTransport();

  @override
  Future<Uri?> start(ReleaseTransportStartRequest request) async => null;

  @override
  Future<void> stop() async {}
}
