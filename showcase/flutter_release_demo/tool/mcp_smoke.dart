// showcase/flutter_release_demo/tool/mcp_smoke.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Drives the release demo from the computer over the real MCP HTTP endpoint.
//
//   adb forward tcp:8765 tcp:8765
//   dart run tool/mcp_smoke.dart --token <pairing token>
//
// Every step prints PASS/FAIL; the process exits non-zero if any step failed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final endpoint = _arg(args, '--endpoint') ?? 'http://127.0.0.1:8765/mcp';
  final token = _arg(args, '--token');
  if (token == null) {
    stderr.writeln(
      'usage: mcp_smoke.dart --token <bearer token> '
      '[--endpoint http://127.0.0.1:8765/mcp]',
    );
    exit(2);
  }

  final client = _Client(Uri.parse(endpoint), token);
  var failures = 0;

  Future<void> step(String name, Future<bool> Function() body) async {
    try {
      final ok = await body();
      stdout.writeln(ok ? 'PASS  $name' : 'FAIL  $name');
      if (!ok) {
        failures += 1;
      }
    } on Object catch (error) {
      stdout.writeln('FAIL  $name ($error)');
      failures += 1;
    }
  }

  await step('initialize handshake', () async {
    final result = await client.initialize();
    final info = result?['serverInfo'];
    stdout.writeln('      server: $info');
    return result != null;
  });

  await step('tools/list exposes 8 tools', () async {
    final tools = await client.listTools();
    final names = tools.map((tool) => tool['name']).toList();
    stdout.writeln('      tools: $names');
    return names.length == 8 &&
        names.contains('ui_click') &&
        names.contains('ui_capture') &&
        names.contains('app_invoke_action');
  });

  await step('ui_get_current_page', () async {
    final payload = await client.callTool('ui_get_current_page', const {});
    stdout.writeln('      page: ${payload?['data']}');
    return payload?['success'] == true;
  });

  String? snapshotId;
  String? incrementRef;
  int counterBefore = 0;

  await step('ui_get_tree finds the Increment button', () async {
    final payload = await client.callTool('ui_get_tree', const {});
    final data = payload?['data'] as Map<String, dynamic>?;
    final nodes = (data?['nodes'] as List<Object?>?) ?? const <Object?>[];
    snapshotId = payload?['snapshotId'] as String?;
    for (final node in nodes) {
      final map = node! as Map<String, dynamic>;
      final label = map['label'];
      if (label is String && label.contains('Increment')) {
        incrementRef = map['ref'] as String?;
      }
    }
    for (final node in nodes) {
      final label = (node! as Map<String, dynamic>)['label'];
      if (label is String && label.startsWith('Counter: ')) {
        counterBefore = int.tryParse(label.substring(9)) ?? 0;
      }
    }
    stdout.writeln(
      '      nodes: ${nodes.length}, snapshot: $snapshotId, '
      'counter: $counterBefore',
    );
    return incrementRef != null && snapshotId != null;
  });

  await step('ui_click taps it', () async {
    final payload = await client.callTool('ui_click', <String, Object?>{
      'ref': incrementRef,
      'snapshotId': snapshotId,
    });
    stdout.writeln('      click: ${payload?['data']}');
    return payload?['success'] == true;
  });

  await step('the screen shows the counter had incremented', () async {
    final payload = await client.callTool('ui_get_tree', const {});
    final data = payload?['data'] as Map<String, dynamic>?;
    final nodes = (data?['nodes'] as List<Object?>?) ?? const <Object?>[];
    snapshotId = payload?['snapshotId'] as String?;
    final expected = 'Counter: ${counterBefore + 1}';
    final seen = nodes
        .map((node) => (node! as Map<String, dynamic>)['label'])
        .whereType<String>()
        .any((label) => label == expected);
    stdout.writeln('      expected "$expected": $seen');
    return seen;
  });

  await step('ui_find_element refuses an ambiguous role query', () async {
    // The screen has two text fields (the token is one), so a role-only query
    // must be refused rather than guessing.
    final payload = await client.callTool('ui_find_element', <String, Object?>{
      'role': 'textField',
    });
    final error = payload?['error'] as Map<String, dynamic>?;
    stdout.writeln(
      '      ambiguity answer: ${error?['code'] ?? payload?['data']}',
    );
    return payload?['success'] != true && error?['code'] == 'ambiguous_match';
  });

  await step('ui_find_element locates the name field by label', () async {
    final payload = await client.callTool('ui_find_element', <String, Object?>{
      'label': 'Your name',
    });
    final data = payload?['data'] as Map<String, dynamic>?;
    final node = data?['node'] as Map<String, dynamic>?;
    if (node != null) {
      incrementRef = node['ref'] as String?;
      snapshotId = payload?['snapshotId'] as String?;
    }
    stdout.writeln('      field: ${node?['label']} ref=${node?['ref']}');
    return node != null;
  });

  await step('ui_set_text writes into it', () async {
    final payload = await client.callTool('ui_set_text', <String, Object?>{
      'ref': incrementRef,
      'text': 'Grace Hopper',
      'snapshotId': snapshotId,
    });
    stdout.writeln('      set_text: ${payload?['data']}');
    return payload?['success'] == true;
  });

  await step('ui_get_tree reads the value back', () async {
    final payload = await client.callTool('ui_get_tree', const {});
    final data = payload?['data'] as Map<String, dynamic>?;
    final nodes = (data?['nodes'] as List<Object?>?) ?? const <Object?>[];
    return nodes
        .map((node) => (node! as Map<String, dynamic>)['value'])
        .whereType<String>()
        .any((value) => value == 'Grace Hopper');
  });

  await step('ui_scroll moves the list', () async {
    final tree = await client.callTool('ui_get_tree', const {});
    final data = tree?['data'] as Map<String, dynamic>?;
    final nodes = (data?['nodes'] as List<Object?>?) ?? const <Object?>[];
    String? scrollRef;
    for (final node in nodes) {
      final map = node! as Map<String, dynamic>;
      final actions = map['actions'];
      if (actions is List &&
          actions.any((action) => '$action'.startsWith('scroll'))) {
        scrollRef = map['ref'] as String?;
        break;
      }
    }
    if (scrollRef == null) {
      stdout.writeln('      no scrollable node in this snapshot');
      return false;
    }
    final payload = await client.callTool('ui_scroll', <String, Object?>{
      'ref': scrollRef,
      'direction': 'down',
      'amount': 200,
      'snapshotId': tree?['snapshotId'],
    });
    stdout.writeln(
      '      scroll: ${payload?['data']} error: ${payload?['error']?['code']} '
      'details: ${payload?['error']?['details']}',
    );
    return payload?['success'] == true;
  });

  await step('app_invoke_action runs the demo action', () async {
    final payload = await client.callTool(
      'app_invoke_action',
      <String, Object?>{'name': 'demo.increment'},
    );
    stdout.writeln('      action: ${payload?['data']}');
    return payload?['success'] == true;
  });

  await step('ui_capture returns a PNG', () async {
    final payload = await client.callTool('ui_capture', <String, Object?>{
      'scale': 0.4,
    });
    final data = payload?['data'] as Map<String, dynamic>?;
    if (data == null) {
      stdout.writeln('      capture error: ${payload?['error']}');
      return false;
    }
    final bytes = base64Decode(data['bytesBase64']! as String);
    final isPng =
        bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    stdout.writeln(
      '      $isPng ? png : not-png  ${data['width']}x${data['height']} '
      '${bytes.length} bytes',
    );
    return isPng;
  });

  await step('an interaction without snapshotId is refused', () async {
    final payload = await client.callTool('ui_click', <String, Object?>{
      'ref': 's_0',
    });
    stdout.writeln('      answered: ${payload?['error']?['code'] ?? payload}');
    return payload == null || payload['success'] != true;
  });

  if (args.contains('--wallet-check')) {
    await step('capture is refused on a policy-blocked route', () async {
      final tree = await client.callTool('ui_get_tree', const {});
      final data = tree?['data'] as Map<String, dynamic>?;
      final nodes = (data?['nodes'] as List<Object?>?) ?? const <Object?>[];
      String? openRef;
      for (final node in nodes) {
        final map = node! as Map<String, dynamic>;
        if (map['label'] == 'Open secret screen') {
          openRef = map['ref'] as String?;
        }
      }
      if (openRef == null) {
        return false;
      }
      final opened = await client.callTool('ui_click', <String, Object?>{
        'ref': openRef,
        'snapshotId': tree?['snapshotId'],
      });
      if (opened?['success'] != true) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final capture = await client.callTool(
        'ui_capture',
        const <String, Object?>{},
      );
      final error = capture?['error'] as Map<String, dynamic>?;
      stdout.writeln('      capture answer: ${error?['code']}');
      final blocked = error?['code'] == 'route_blocked';

      // Back to the demo screen for whoever runs this next.
      await Process.run('adb', <String>['shell', 'input', 'keyevent', '4']);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return blocked;
    });
  }

  stdout.writeln('');
  stdout.writeln(
    failures == 0 ? 'ALL STEPS PASSED' : '$failures STEP(S) FAILED',
  );
  exit(failures == 0 ? 0 : 1);
}

String? _arg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

final class _Client {
  _Client(this.endpoint, this.token);

  final Uri endpoint;
  final String token;
  String? _sessionId;
  int _nextId = 1;

  Future<Map<String, dynamic>?> initialize() async {
    final response = await _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'initialize',
      'params': <String, dynamic>{
        'protocolVersion': '2025-06-18',
        'capabilities': <String, dynamic>{},
        'clientInfo': <String, dynamic>{
          'name': 'release-demo-smoke',
          'version': '1.0.0',
        },
      },
    });
    if (response.statusCode != 200) {
      throw StateError('initialize failed: HTTP ${response.statusCode}');
    }
    _sessionId = response.headers['mcp-session-id'];
    await _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
    return response.payload?['result'] as Map<String, dynamic>?;
  }

  Future<List<Map<String, dynamic>>> listTools() async {
    final response = await _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'tools/list',
    });
    final result = response.payload?['result'] as Map<String, dynamic>?;
    final tools = (result?['tools'] as List<Object?>?) ?? const <Object?>[];
    return <Map<String, dynamic>>[
      for (final tool in tools)
        if (tool is Map<String, dynamic>) tool,
    ];
  }

  Future<Map<String, dynamic>?> callTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final response = await _send(
      <String, dynamic>{
        'jsonrpc': '2.0',
        'id': _nextId++,
        'method': 'tools/call',
        'params': <String, dynamic>{'name': name, 'arguments': arguments},
      },
      headers: <String, String>{'mcp-name': name, 'mcp-method': 'tools/call'},
    );
    final result = response.payload?['result'];
    if (result is! Map<String, dynamic>) {
      return <String, dynamic>{
        'success': false,
        'error': <String, Object?>{'code': 'protocol', 'raw': response.rawBody},
      };
    }
    final content = result['content'] as List<Object?>?;
    if (content == null || content.isEmpty) {
      return <String, dynamic>{'success': result['isError'] != true};
    }
    final text = (content.first as Map<String, dynamic>)['text'];
    if (text is! String) {
      return <String, dynamic>{'success': false};
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
      headers.forEach(request.headers.set);
      request.write(jsonEncode(body));
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(', ');
      });
      return _Response(response.statusCode, responseHeaders, _decode(raw), raw);
    } finally {
      http.close(force: true);
    }
  }

  static Map<String, dynamic>? _decode(String raw) {
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
}

final class _Response {
  _Response(this.statusCode, this.headers, this.payload, this.rawBody);

  final int statusCode;
  final Map<String, String> headers;
  final Map<String, dynamic>? payload;
  final String rawBody;
}
