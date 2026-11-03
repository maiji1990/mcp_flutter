// packages/release_runtime/lib/src/server/http_transport.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime). Depends on the published
// `mcp_server` package for the Streamable HTTP protocol implementation; this
// file owns only the release-specific policy around it.

import 'package:mcp_server/mcp_server.dart' as mcp;

import '../errors/release_mcp_error.dart';
import '../runtime_version.dart';
import '../transport/runtime_transport.dart';

/// Streamable HTTP transport for the release runtime.
///
/// Policy this class pins down (the SDK's defaults are aimed at general
/// servers, not at a process inside someone's phone):
///
/// - **No fallback ports.** `fallbackPorts` is empty, so a taken port is a
///   failed start (`transport_start_failed`) instead of a silent rebind onto
///   `port + 1`.
/// - **Bearer token required.** Every request must carry
///   `Authorization: Bearer <token>`; missing or wrong → 401 before dispatch.
/// - **Origin allow-list stays on.** The SDK's default allow-list is the local
///   machine, and `allowAnyOrigin` stays false, so a remote page cannot drive
///   the phone's app through DNS rebinding.
/// - **No wildcard CORS.** `Access-Control-Allow-Origin` names the loopback
///   origin instead of `*`.
/// - **Bounds from config.** Request body ceiling, per-request timeout, and
///   session count come from [ReleaseTransportStartRequest], not SDK defaults.
/// - **JSON responses, no GET stream.** `isJsonResponseEnabled` keeps one
///   request/one response, and `enableGetStream: false` answers GET with 405.
///
/// The MCP protocol work (initialize, sessions, tools/list, batching, protocol
/// version negotiation) is the SDK's, not a hand-rolled implementation.
final class HttpReleaseRuntimeTransport implements ReleaseRuntimeTransport {
  HttpReleaseRuntimeTransport({
    this.serverName = 'flutter_mcp_toolkit_release',
    this.serverVersion = kReleaseRuntimeVersion,
  });

  /// `serverInfo.name` reported during `initialize`.
  final String serverName;

  /// `serverInfo.version` reported during `initialize`.
  final String serverVersion;

  mcp.Server? _server;
  mcp.StreamableHttpServerTransport? _transport;
  Uri? _endpoint;

  @override
  Future<Uri?> start(ReleaseTransportStartRequest request) async {
    if (_transport != null) {
      throw ReleaseMcpException(
        ReleaseMcpErrorCode.invalidStateTransition,
        details: <String, Object?>{'reason': 'transport_already_started'},
      );
    }

    final server = mcp.McpServer.createServer(
      mcp.McpServerConfig(
        name: serverName,
        version: serverVersion,
        capabilities: mcp.ServerCapabilities.simple(tools: true),
        maxConnections: request.maxConcurrentRequests,
      ),
    );

    final transport = mcp.StreamableHttpServerTransport(
      config: mcp.StreamableHttpServerConfig(
        host: request.host,
        port: request.port,
        endpoint: request.endpoint,
        fallbackPorts: const <int>[],
        authToken: request.accessToken,
        maxRequestSize: request.maxRequestBytes,
        requestTimeout: request.requestTimeout,
        isJsonResponseEnabled: true,
        enableGetStream: false,
        corsConfig: mcp.CorsConfig(
          allowOrigin: 'http://${_hostForUri(request.host)}',
        ),
      ),
    );

    try {
      await transport.start();
    } catch (error) {
      transport.close();
      server.dispose();
      throw ReleaseMcpException(
        ReleaseMcpErrorCode.transportStartFailed,
        details: <String, Object?>{'cause': error.runtimeType.toString()},
      );
    }

    server.connect(transport);
    _server = server;
    _transport = transport;

    final boundPort = transport.boundPort ?? request.port;
    final endpoint = Uri.parse(
      'http://${_hostForUri(request.host)}:$boundPort${request.endpoint}',
    );
    _endpoint = endpoint;
    return endpoint;
  }

  @override
  Future<void> stop() async {
    final transport = _transport;
    final server = _server;
    _transport = null;
    _server = null;
    _endpoint = null;

    try {
      if (transport != null) {
        // `close()` is declared void-async by the SDK, so the awaitable signal
        // is `onClose`, which completes once the listening socket is shut.
        transport.close();
        await transport.onClose.timeout(const Duration(seconds: 5));
      }
    } finally {
      server?.dispose();
    }
  }

  /// The endpoint this transport is currently bound to, or null.
  Uri? get endpoint => _endpoint;

  static String _hostForUri(String host) =>
      host.contains(':') ? '[$host]' : host;
}
