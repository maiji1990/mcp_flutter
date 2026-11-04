// showcase/flutter_release_demo/tool/mcp_ping.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// One initialize over the release endpoint, for lifecycle checks:
//   dart run tool/mcp_ping.dart --token <token>
// Exit code 0 = server answered; 1 = HTTP/protocol failure; 2 = unreachable.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final tokenIndex = args.indexOf('--token');
  if (tokenIndex < 0 || tokenIndex + 1 >= args.length) {
    stderr.writeln('usage: mcp_ping.dart --token <token>');
    exit(2);
  }
  final token = args[tokenIndex + 1];
  final endpoint = Uri.parse(
    args.contains('--endpoint')
        ? args[args.indexOf('--endpoint') + 1]
        : 'http://127.0.0.1:8765/mcp',
  );
  final client = HttpClient();
  try {
    final request = await client.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/event-stream',
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.write(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, dynamic>{
          'protocolVersion': '2025-06-18',
          'capabilities': <String, dynamic>{},
          'clientInfo': <String, dynamic>{'name': 'ping', 'version': '1'},
        },
      }),
    );
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      stdout.writeln('HTTP ${response.statusCode}');
      exit(1);
    }
    final decoded = jsonDecode(raw);
    final result = decoded is Map ? decoded['result'] : null;
    if (result is Map) {
      stdout.writeln('OK ${result['serverInfo']}');
      exit(0);
    }
    stdout.writeln('NO RESULT');
    exit(1);
  } on SocketException catch (error) {
    stdout.writeln('UNREACHABLE ${error.osError?.errorCode ?? error.message}');
    exit(2);
  } on HttpException catch (error) {
    stdout.writeln('UNREACHABLE ${error.message}');
    exit(2);
  } on Object catch (error) {
    stdout.writeln('ERROR ${error.runtimeType}');
    exit(1);
  } finally {
    client.close(force: true);
  }
}
