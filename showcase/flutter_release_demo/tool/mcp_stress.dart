// showcase/flutter_release_demo/tool/mcp_stress.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Sends N cheap calls to exercise the rate limiter:
//   dart run tool/mcp_stress.dart --token <token> --calls 130
// Prints how many succeeded and how many were rate_limited.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final tokenIndex = args.indexOf('--token');
  if (tokenIndex < 0 || tokenIndex + 1 >= args.length) {
    stderr.writeln('usage: mcp_stress.dart --token <token> [--calls 130]');
    exit(2);
  }
  final token = args[tokenIndex + 1];
  final callsIndex = args.indexOf('--calls');
  final calls = callsIndex >= 0 ? int.parse(args[callsIndex + 1]) : 130;
  final http = HttpClient();
  String? sessionId;
  var id = 0;

  Future<Map<String, dynamic>?> send(Map<String, dynamic> body) async {
    final request = await http.postUrl(Uri.parse('http://127.0.0.1:8765/mcp'));
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
    sessionId ??= response.headers.value('mcp-session-id');
    final raw = await response.transform(utf8.decoder).join();
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) {
      return null;
    }
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  await send(<String, dynamic>{
    'jsonrpc': '2.0',
    'id': ++id,
    'method': 'initialize',
    'params': <String, dynamic>{
      'protocolVersion': '2025-06-18',
      'capabilities': <String, dynamic>{},
      'clientInfo': <String, dynamic>{'name': 'stress', 'version': '1'},
    },
  });
  await send(<String, dynamic>{
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });

  var ok = 0;
  var limited = 0;
  var other = 0;
  for (var i = 0; i < calls; i += 1) {
    final response = await send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': ++id,
      'method': 'tools/call',
      'params': <String, dynamic>{
        'name': 'ui_get_current_page',
        'arguments': <String, Object?>{},
      },
    });
    final result = response?['result'] as Map<String, dynamic>?;
    final content = result?['content'] as List<Object?>?;
    if (content == null || content.isEmpty) {
      other += 1;
      continue;
    }
    final payload = jsonDecode(
      (content.first as Map<String, dynamic>)['text'] as String,
    ) as Map<String, dynamic>;
    if (payload['success'] == true) {
      ok += 1;
    } else if ((payload['error'] as Map?)?['code'] == 'rate_limited') {
      limited += 1;
    } else {
      other += 1;
    }
  }
  stdout.writeln('calls=$calls ok=$ok rate_limited=$limited other=$other');
  http.close(force: true);
  exit(limited > 0 ? 0 : 1);
}
