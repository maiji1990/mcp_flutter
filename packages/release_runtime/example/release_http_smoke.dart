// packages/release_runtime/example/release_http_smoke.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).
//
// End-to-end smoke test you can run from the computer:
//
//   dart run packages/release_runtime/example/release_http_smoke.dart
//
// It starts the runtime exactly the way a release app would (loopback, random
// port, bearer token), performs a real MCP handshake over HTTP, proves that an
// unauthenticated request is refused, and then stops.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';

Future<void> main() async {
  final runtime = ReleaseMcpRuntime.http(
    config: const ReleaseMcpConfig(port: 0, endpoint: '/mcp'),
  );
  final status = await runtime.start(
    authorization: ReleaseStartAuthorization.readOnly(reason: 'smoke test'),
  );
  final endpoint = status.endpoint!;
  final token = runtime.accessToken;

  stdout.writeln('state:      ${status.state.wireName}');
  stdout.writeln('endpoint:   $endpoint');
  stdout.writeln('read-only:  ${status.isReadOnly}');
  stdout.writeln('token:      $token');

  final unauthorized = await _post(endpoint, _initializeBody(), token: null);
  stdout.writeln('no token:   HTTP ${unauthorized.statusCode}');

  final initialize = await _post(
    endpoint,
    _initializeBody(),
    token: token.value,
  );
  final sessionId = initialize.headers['mcp-session-id'];
  stdout.writeln(
    'initialize: HTTP ${initialize.statusCode} session=$sessionId',
  );
  stdout.writeln(
    '  serverInfo: ${(initialize.payload?['result'] as Map?)?['serverInfo']}',
  );

  final list = await _post(
    endpoint,
    <String, dynamic>{'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
    token: token.value,
    sessionId: sessionId,
  );
  stdout.writeln(
    'tools/list: HTTP ${list.statusCode} ${jsonEncode(list.payload?['result'])}',
  );

  await runtime.stop();
  stdout.writeln(
    'after stop: state=${runtime.state.wireName} endpoint=${runtime.status.endpoint}',
  );
  await runtime.dispose();
}

Map<String, dynamic> _initializeBody() => <String, dynamic>{
  'jsonrpc': '2.0',
  'id': 1,
  'method': 'initialize',
  'params': <String, dynamic>{
    'protocolVersion': '2025-06-18',
    'capabilities': <String, dynamic>{},
    'clientInfo': <String, dynamic>{'name': 'smoke', 'version': '0.0.1'},
  },
};

Future<
  ({int statusCode, Map<String, String> headers, Map<String, dynamic>? payload})
>
_post(
  Uri uri,
  Map<String, dynamic> body, {
  String? token,
  String? sessionId,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/event-stream',
    );
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (sessionId != null) {
      request.headers.set('mcp-session-id', sessionId);
    }
    request.write(jsonEncode(body));

    final response = await request.close();
    final rawBody = await response.transform(utf8.decoder).join();
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });
    return (
      statusCode: response.statusCode,
      headers: headers,
      payload: _decodePayload(rawBody),
    );
  } finally {
    client.close(force: true);
  }
}

Map<String, dynamic>? _decodePayload(String rawBody) {
  final trimmed = rawBody.trim();
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
