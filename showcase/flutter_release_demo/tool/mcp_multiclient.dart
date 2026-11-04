// showcase/flutter_release_demo/tool/mcp_multiclient.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Two independent MCP sessions against one runtime, for the AUTH-02 probe:
//   dart run tool/mcp_multiclient.dart --token <token>
// Prints what each session can do. Exit 0 when both sessions complete the
// read; the shared-grant observation is data, not a failure.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final tokenIndex = args.indexOf('--token');
  if (tokenIndex < 0 || tokenIndex + 1 >= args.length) {
    stderr.writeln('usage: mcp_multiclient.dart --token <token>');
    exit(2);
  }
  final token = args[tokenIndex + 1];
  final a = _Client(token);
  final b = _Client(token);
  await a.initialize();
  await b.initialize();
  stdout.writeln('sessions: A=${a.sessionId != null} B=${b.sessionId != null}');

  final results = await Future.wait(<Future<Map<String, dynamic>?>>[
    a.callTool('ui_get_tree', const <String, Object?>{}),
    b.callTool('ui_get_tree', const <String, Object?>{}),
  ]);
  final aOk = results[0]?['success'] == true;
  final bOk = results[1]?['success'] == true;
  stdout.writeln('concurrent ui_get_tree: A=$aOk B=$bOk');

  final actionA = await a.callTool('app_invoke_action', <String, Object?>{
    'name': 'demo.increment',
  });
  final actionB = await b.callTool('app_invoke_action', <String, Object?>{
    'name': 'demo.increment',
  });
  stdout.writeln(
    'app action without per-session grant: '
    'A=${actionA?['success']} B=${actionB?['success']} '
    '(shared runtime grant)',
  );
  exit(aOk && bOk ? 0 : 1);
}

final class _Client {
  _Client(this.token);

  final String token;
  String? sessionId;
  int _id = 0;

  Future<void> initialize() async {
    final response = await _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': ++_id,
      'method': 'initialize',
      'params': <String, dynamic>{
        'protocolVersion': '2025-06-18',
        'capabilities': <String, dynamic>{},
        'clientInfo': <String, dynamic>{'name': 'multi', 'version': '1'},
      },
    });
    sessionId = response.headers['mcp-session-id'];
    await _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
  }

  Future<Map<String, dynamic>?> callTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final response = await _send(
      <String, dynamic>{
        'jsonrpc': '2.0',
        'id': ++_id,
        'method': 'tools/call',
        'params': <String, dynamic>{'name': name, 'arguments': arguments},
      },
      headers: <String, String>{'mcp-name': name, 'mcp-method': 'tools/call'},
    );
    final result = response.payload?['result'];
    if (result is! Map) {
      return null;
    }
    final content = result['content'] as List<Object?>?;
    if (content == null || content.isEmpty) {
      return <String, dynamic>{'success': result['isError'] != true};
    }
    final text = (content.first as Map<String, dynamic>)['text'];
    if (text is! String) {
      return null;
    }
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<_Response> _send(
    Map<String, dynamic> body, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final http = HttpClient();
    try {
      final request = await http.postUrl(
        Uri.parse('http://127.0.0.1:8765/mcp'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/event-stream',
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (sessionId != null) {
        request.headers.set('mcp-session-id', sessionId!);
      }
      headers.forEach(request.headers.set);
      request.write(jsonEncode(body));
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      final map = <String, String>{};
      response.headers.forEach((name, values) {
        map[name.toLowerCase()] = values.join(', ');
      });
      return _Response(map, _decode(raw));
    } finally {
      http.close(force: true);
    }
  }

  static Map<String, dynamic>? _decode(String raw) {
    final trimmed = raw.trim();
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
}

final class _Response {
  const _Response(this.headers, this.payload);

  final Map<String, String> headers;
  final Map<String, dynamic>? payload;
}
