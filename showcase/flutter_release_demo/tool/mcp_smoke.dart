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

  await step('tools/list exposes the Flutter and web tools', () async {
    final tools = await client.listTools();
    final names = tools.map((tool) => tool['name']).toList();
    stdout.writeln('      tools: $names');
    return names.length == 15 &&
        names.contains('ui_click') &&
        names.contains('ui_capture') &&
        names.contains('app_invoke_action') &&
        names.contains('web_get_tree') &&
        names.contains('web_click');
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

  await step(
    'app_invoke_action rejects arguments the schema forbids',
    () async {
      final payload = await client.callTool(
        'app_invoke_action',
        <String, Object?>{
          'name': 'demo.increment',
          'arguments': <String, Object?>{'unexpected': true},
        },
      );
      final error = payload?['error'] as Map<String, dynamic>?;
      stdout.writeln('      invalid action answer: ${error?['code']}');
      return payload?['success'] != true &&
          error?['code'] == 'invalid_argument';
    },
  );

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

  if (args.contains('--webview-check')) {
    await step('opens the WebView demo and registers the view', () async {
      final tree = await client.callTool('ui_get_tree', const {});
      final data = tree?['data'] as Map<String, dynamic>?;
      final nodes = (data?['nodes'] as List<Object?>?) ?? const <Object?>[];
      String? openRef;
      for (final node in nodes) {
        final map = node! as Map<String, dynamic>;
        if (map['label'] == 'Open WebView demo') {
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
      await Future<void>.delayed(const Duration(seconds: 3));
      final views = await client.callTool('web_list_views', const {});
      final list =
          (views?['data']?['views'] as List<Object?>?) ?? const <Object?>[];
      stdout.writeln('      views: $list');
      return list.any((view) => view is Map && view['viewId'] == 'order-h5');
    });

    String? webSnapshot;
    String? searchRef;
    await step('web_get_tree reads the H5 DOM and masks the PIN', () async {
      final tree = await client.callTool('web_get_tree', <String, Object?>{
        'viewId': 'order-h5',
      });
      final data = tree?['data'] as Map<String, dynamic>?;
      final nodes = (data?['nodes'] as List<Object?>?) ?? const <Object?>[];
      webSnapshot = tree?['snapshotId'] as String?;
      final url = data?['url'];
      if (tree?['success'] != true) {
        stdout.writeln('      tree error: ${tree?['error']}');
      }

      for (final node in nodes) {
        final map = node! as Map<String, dynamic>;
        if ('${map['label']}'.startsWith('Search order')) {
          searchRef = map['ref'] as String?;
        }
      }
      final passwordNodes = nodes
          .cast<Map<String, dynamic>>()
          .where((node) => node['type'] == 'password')
          .toList();
      final masked =
          passwordNodes.isNotEmpty &&
          passwordNodes.every((node) => node['value'] == '••••');
      final leaked = jsonEncode(tree).contains('1234');
      stdout.writeln(
        '      url: $url nodes: ${nodes.length} pinMasked: $masked',
      );
      return tree?['success'] == true &&
          url is String &&
          url.contains('127.0.0.1') &&
          searchRef != null &&
          masked &&
          !leaked;
    });

    await step('web_set_text fills the search field', () async {
      final result = await client.callTool('web_set_text', <String, Object?>{
        'viewId': 'order-h5',
        'ref': searchRef,
        'snapshotId': webSnapshot,
        'text': 'INV-42',
      });
      final error = result?['error'] as Map<String, dynamic>?;
      stdout.writeln('      set_text: ${result?['data'] ?? error}');
      return result?['success'] == true;
    });

    String? clickSnapshot;
    await step('web_click runs the page button', () async {
      final tree = await client.callTool('web_get_tree', <String, Object?>{
        'viewId': 'order-h5',
      });
      final data = tree?['data'] as Map<String, dynamic>?;
      final nodes = (data?['nodes'] as List<Object?>?) ?? const <Object?>[];
      webSnapshot = tree?['snapshotId'] as String?;
      String? buttonRef;
      for (final node in nodes) {
        final map = node! as Map<String, dynamic>;
        if (map['tag'] == 'button' && map['label'] == 'Search') {
          buttonRef = map['ref'] as String?;
        }
      }
      if (buttonRef == null) {
        return false;
      }
      clickSnapshot = webSnapshot;
      final result = await client.callTool('web_click', <String, Object?>{
        'viewId': 'order-h5',
        'ref': buttonRef,
        'snapshotId': webSnapshot,
      });
      final error = result?['error'] as Map<String, dynamic>?;
      stdout.writeln('      click: ${result?['data'] ?? error}');
      return result?['success'] == true;
    });

    await step('web_get_tree sees the page result', () async {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final tree = await client.callTool('web_get_tree', <String, Object?>{
        'viewId': 'order-h5',
      });
      final found = jsonEncode(tree).contains('Result for INV-42');
      stdout.writeln('      result visible: $found');
      return found;
    });

    await step('a consumed WebView snapshot cannot be replayed', () async {
      final replay = await client.callTool('web_click', <String, Object?>{
        'viewId': 'order-h5',
        'ref': 'w0_0',
        'snapshotId': clickSnapshot,
      });
      final error = replay?['error'] as Map<String, dynamic>?;
      stdout.writeln('      replay: ${error?['code']}');
      return replay?['success'] != true && error?['code'] == 'stale_snapshot';
    });

    await step('web_set_text drives a controlled input', () async {
      final tree = await client.callTool('web_get_tree', <String, Object?>{
        'viewId': 'order-h5',
      });
      final data = tree?['data'] as Map<String, dynamic>?;
      final nodes = (data?['nodes'] as List<Object?>?) ?? const <Object?>[];
      String? noteRef;
      for (final node in nodes) {
        final map = node! as Map<String, dynamic>;
        if ('${map['label']}' == 'Controlled note') {
          noteRef = map['ref'] as String?;
        }
      }
      if (noteRef == null) {
        stdout.writeln('      controlled input not found');
        return false;
      }
      final result = await client.callTool('web_set_text', <String, Object?>{
        'viewId': 'order-h5',
        'ref': noteRef,
        'snapshotId': tree?['snapshotId'],
        'text': 'hello frame',
      });
      final error = result?['error'] as Map<String, dynamic>?;
      stdout.writeln('      controlled set_text: ${result?['data'] ?? error}');
      return result?['success'] == true;
    });

    await step('the controlled view re-rendered from state', () async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final tree = await client.callTool('web_get_tree', <String, Object?>{
        'viewId': 'order-h5',
      });
      final found = jsonEncode(tree).contains('Model: hello frame');
      stdout.writeln('      controlled model visible: $found');
      return tree?['success'] == true && found;
    });

    String? beforeSpa;
    await step('web_click follows a SPA History navigation', () async {
      final tree = await client.callTool('web_get_tree', <String, Object?>{
        'viewId': 'order-h5',
      });
      final data = tree?['data'] as Map<String, dynamic>?;
      final nodes = (data?['nodes'] as List<Object?>?) ?? const <Object?>[];
      beforeSpa = tree?['snapshotId'] as String?;
      String? detailsRef;
      for (final node in nodes) {
        final map = node! as Map<String, dynamic>;
        if ('${map['label']}' == 'Open details') {
          detailsRef = map['ref'] as String?;
        }
      }
      if (detailsRef == null) {
        return false;
      }
      final result = await client.callTool('web_click', <String, Object?>{
        'viewId': 'order-h5',
        'ref': detailsRef,
        'snapshotId': beforeSpa,
      });
      final error = result?['error'] as Map<String, dynamic>?;
      stdout.writeln('      spa click: ${result?['data'] ?? error}');
      return result?['success'] == true;
    });

    await step('the SPA route advanced the epoch and the old ref is stale', () async {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final tree = await client.callTool('web_get_tree', <String, Object?>{
        'viewId': 'order-h5',
      });
      final data = tree?['data'] as Map<String, dynamic>?;
      final details = jsonEncode(tree).contains('Details page');
      final epoch = data?['navigationEpoch'] as int? ?? 0;
      final replay = await client.callTool('web_click', <String, Object?>{
        'viewId': 'order-h5',
        'ref': 'w0_0',
        'snapshotId': beforeSpa,
      });
      final replayError = replay?['error'] as Map<String, dynamic>?;
      final stale = replayError?['code'] == 'stale_snapshot';
      stdout.writeln(
        '      spa: url=${data?['url']} epoch=$epoch details=$details stale=$stale',
      );
      return tree?['success'] == true && details && epoch >= 2 && stale;
    });

    await step('a cross-origin iframe is not traversed', () async {
      final tree = await client.callTool('web_get_tree', <String, Object?>{
        'viewId': 'order-h5',
      });
      final leaked = jsonEncode(tree).contains('Inside frame');
      stdout.writeln('      iframe content leaked: $leaked');
      return tree?['success'] == true && !leaked;
    });

    await step('ui_capture returns the hybrid WebView screen', () async {
      final capture = await client.callTool('ui_capture', <String, Object?>{
        'scale': 0.5,
      });
      final data = capture?['data'] as Map<String, dynamic>?;
      final base64 = data?['bytesBase64'] as String?;
      if (base64 == null) {
        stdout.writeln('      hybrid capture error: ${capture?['error']}');
        return false;
      }
      final bytes = base64Decode(base64);
      final isPng = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50;
      final dir = _arg(args, '--capture-dir');
      if (dir != null) {
        Directory(dir).createSync(recursive: true);
        File('$dir/web-demo.png').writeAsBytesSync(bytes);
      }
      stdout.writeln(
        '      hybrid capture: ${data?['width']}x${data?['height']} '
        '${bytes.length} bytes png=$isPng',
      );
      return isPng;
    });

    await step('web_get_state reports the loopback origin', () async {
      final state = await client.callTool('web_get_state', <String, Object?>{
        'viewId': 'order-h5',
      });
      final data = state?['data'] as Map<String, dynamic>?;
      stdout.writeln('      state: $data');
      return state?['success'] == true &&
          (data?['url']).toString().contains('127.0.0.1');
    });

    await Process.run('adb', <String>['shell', 'input', 'keyevent', '4']);
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

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

      final walletTree = await client.callTool('ui_get_tree', const {});
      final walletError = walletTree?['error'] as Map<String, dynamic>?;
      final readBlocked = walletError?['code'] == 'route_denied';
      final leaked = jsonEncode(walletTree).contains('4111');
      stdout.writeln(
        '      wallet read: ${walletError?['code']} leaked=$leaked',
      );

      final capture = await client.callTool(
        'ui_capture',
        const <String, Object?>{},
      );
      final error = capture?['error'] as Map<String, dynamic>?;
      stdout.writeln('      capture answer: ${error?['code']}');
      final blocked = error?['code'] == 'route_blocked';
      final noBytes = !jsonEncode(capture).contains('bytesBase64');

      // Back to the demo screen for whoever runs this next.
      await Process.run('adb', <String>['shell', 'input', 'keyevent', '4']);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return blocked && noBytes && readBlocked && !leaked;
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
