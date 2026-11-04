// showcase/flutter_release_demo/tool/mcp_probe.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Prints the nodes the device reports, for debugging a fixture:
//   dart run tool/mcp_probe.dart --token <token> [--route /wallet]

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final tokenIndex = args.indexOf('--token');
  if (tokenIndex < 0 || tokenIndex + 1 >= args.length) {
    stderr.writeln('usage: mcp_probe.dart --token <token>');
    exit(2);
  }
  final token = args[tokenIndex + 1];
  final endpoint = Uri.parse('http://127.0.0.1:8765/mcp');
  final client = HttpClient();
  String? sessionId;
  var nextId = 1;

  Future<Map<String, dynamic>?> send(Map<String, dynamic> body) async {
    final request = await client.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/event-stream',
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (sessionId != null) {
      request.headers.set('mcp-session-id', sessionId!);
    }
    request.write(jsonEncode(body));
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    sessionId ??= response.headers.value('mcp-session-id');
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) {
      return null;
    }
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  await send(<String, dynamic>{
    'jsonrpc': '2.0',
    'id': nextId++,
    'method': 'initialize',
    'params': <String, dynamic>{
      'protocolVersion': '2025-06-18',
      'capabilities': <String, dynamic>{},
      'clientInfo': <String, dynamic>{'name': 'probe', 'version': '1'},
    },
  });
  await send(<String, dynamic>{
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });

  final response = await send(<String, dynamic>{
    'jsonrpc': '2.0',
    'id': nextId++,
    'method': 'tools/call',
    'params': <String, dynamic>{
      'name': 'ui_get_tree',
      'arguments': <String, Object?>{},
    },
  });
  final result = response?['result'] as Map<String, dynamic>?;
  final content = result?['content'] as List<Object?>?;
  if (content == null || content.isEmpty) {
    stdout.writeln('no content: $response');
    exit(1);
  }
  final payload = jsonDecode(
    (content.first as Map<String, dynamic>)['text'] as String,
  ) as Map<String, dynamic>;
  final data = payload['data'] as Map<String, dynamic>?;
  final nodes = (data?['nodes'] as List<Object?>?) ?? const <Object?>[];
  stdout.writeln('snapshot=${payload['snapshotId']} nodes=${nodes.length}');
  for (final node in nodes) {
    final map = node! as Map<String, dynamic>;
    stdout.writeln(
      '${map['ref']} type=${map['type']} label=${map['label']} '
      'id=${map['identifier']} value=${map['value']} '
      'actions=${map['actions']}',
    );
  }
  client.close(force: true);
}
