// packages/release_runtime/test/support/mcp_http_client.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'dart:convert';
import 'dart:io';

/// Minimal MCP client over HTTP, for tests that need to speak the protocol
/// rather than assert raw status codes.
final class McpTestClient {
  McpTestClient(this.endpoint, this.token);

  final Uri endpoint;
  final String token;

  int _nextId = 1;
  String? _sessionId;

  /// Performs the `initialize` handshake and remembers the session id.
  Future<Map<String, dynamic>?> initialize() async {
    final response = await send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'initialize',
      'params': <String, dynamic>{
        'protocolVersion': '2025-06-18',
        'capabilities': <String, dynamic>{},
        'clientInfo': <String, dynamic>{'name': 'release-runtime-test'},
      },
    });
    if (response.statusCode != 200) {
      throw StateError('initialize failed: HTTP ${response.statusCode}');
    }
    _sessionId = response.headers['mcp-session-id'];
    await send(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
    return response.payload?['result'] as Map<String, dynamic>?;
  }

  String? get sessionId => _sessionId;

  Future<List<Map<String, dynamic>>> listTools() async {
    final response = await send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'tools/list',
    });
    final result = response.payload?['result'] as Map<String, dynamic>?;
    final tools = result?['tools'];
    if (tools is! List) {
      return const <Map<String, dynamic>>[];
    }
    return <Map<String, dynamic>>[
      for (final tool in tools)
        if (tool is Map<String, dynamic>) tool,
    ];
  }

  /// Calls a tool and returns the decoded `result` of the JSON-RPC response.
  Future<Map<String, dynamic>?> callTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final response = await send(
      <String, dynamic>{
        'jsonrpc': '2.0',
        'id': _nextId++,
        'method': 'tools/call',
        'params': <String, dynamic>{'name': name, 'arguments': arguments},
      },
      extraHeaders: <String, String>{
        'mcp-name': name,
        'mcp-method': 'tools/call',
      },
    );
    return response.payload?['result'] as Map<String, dynamic>?;
  }

  Future<McpHttpResponse> send(
    Map<String, dynamic> body, {
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final http = HttpClient();
    try {
      final request = await http.postUrl(endpoint);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/event-stream',
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (_sessionId != null) {
        request.headers.set('mcp-session-id', _sessionId!);
      }
      extraHeaders.forEach(request.headers.set);
      request.write(jsonEncode(body));

      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(', ');
      });
      return McpHttpResponse(response.statusCode, headers, _decode(raw), raw);
    } finally {
      http.close(force: true);
    }
  }
}

Map<String, dynamic>? _decode(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.startsWith('{')) {
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
  Map<String, dynamic>? last;
  for (final line in const LineSplitter().convert(trimmed)) {
    if (!line.startsWith('data:')) {
      continue;
    }
    final data = line.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') {
      continue;
    }
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic>) {
      last = decoded;
    }
  }
  return last;
}

/// Raw response of one MCP request.
final class McpHttpResponse {
  const McpHttpResponse(
    this.statusCode,
    this.headers,
    this.payload,
    this.rawBody,
  );

  final int statusCode;
  final Map<String, String> headers;
  final Map<String, dynamic>? payload;
  final String rawBody;
}

/// Decodes the JSON envelope a release tool returns in its text content.
Map<String, dynamic> releasePayloadOf(Map<String, dynamic> result) {
  final content = result['content'];
  if (content is! List || content.isEmpty) {
    return <String, dynamic>{};
  }
  final first = content.first;
  if (first is! Map) {
    return <String, dynamic>{};
  }
  final text = first['text'];
  if (text is! String) {
    return <String, dynamic>{};
  }
  final decoded = jsonDecode(text);
  return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
}
