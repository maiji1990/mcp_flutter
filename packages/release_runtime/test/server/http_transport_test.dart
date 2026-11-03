// packages/release_runtime/test/server/http_transport_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

/// A decoded HTTP response from the MCP endpoint.
final class _Response {
  _Response(this.statusCode, this.headers, this.payload, this.rawBody);

  final int statusCode;
  final Map<String, String> headers;
  final Map<String, dynamic>? payload;
  final String rawBody;
}

Map<String, dynamic> _initializeBody({int id = 1}) => <String, dynamic>{
  'jsonrpc': '2.0',
  'id': id,
  'method': 'initialize',
  'params': <String, dynamic>{
    'protocolVersion': '2025-06-18',
    'capabilities': <String, dynamic>{},
    'clientInfo': <String, dynamic>{
      'name': 'release-runtime-test',
      'version': '0.0.1',
    },
  },
};

Future<_Response> _post(
  Uri uri,
  Map<String, dynamic> body, {
  String? token,
  String? sessionId,
  String? origin,
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
    if (origin != null) {
      request.headers.set('origin', origin);
    }
    request.write(jsonEncode(body));
    final response = await request.close();
    final rawBody = await response.transform(utf8.decoder).join();
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });
    return _Response(
      response.statusCode,
      headers,
      _decodePayload(rawBody),
      rawBody,
    );
  } finally {
    client.close(force: true);
  }
}

Future<int> _getStatus(Uri uri, {String? token, String? origin}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (origin != null) {
      request.headers.set('origin', origin);
    }
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// Accepts a JSON body or an SSE stream, since the transport is allowed to
/// answer either way.
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

void main() {
  group('ReleaseMcpRuntime.http', () {
    late ReleaseMcpRuntime runtime;
    late Uri endpoint;
    late String token;

    setUp(() async {
      runtime = ReleaseMcpRuntime.http(config: const ReleaseMcpConfig(port: 0));
      token = runtime.accessToken.value;
      final status = await runtime.start();
      endpoint = status.endpoint!;
    });

    tearDown(() async {
      await runtime.dispose();
    });

    test('binds an ephemeral loopback endpoint and reports it', () {
      expect(endpoint.scheme, 'http');
      expect(endpoint.host, '127.0.0.1');
      expect(endpoint.port, greaterThan(0));
      expect(endpoint.path, '/mcp');
      expect(runtime.status.isListening, isTrue);
      expect(runtime.state, ReleaseRuntimeState.running);
    });

    test('answers initialize and tools/list with the bearer token', () async {
      final initialize = await _post(endpoint, _initializeBody(), token: token);

      expect(initialize.statusCode, 200);
      final initResult = initialize.payload?['result'] as Map<String, dynamic>?;
      expect(initResult, isNotNull, reason: initialize.rawBody);
      expect(
        (initResult!['serverInfo'] as Map<String, dynamic>)['name'],
        'flutter_mcp_toolkit_release',
      );
      final sessionId = initialize.headers['mcp-session-id'];
      expect(sessionId, isNotNull);

      final list = await _post(
        endpoint,
        <String, dynamic>{'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
        token: token,
        sessionId: sessionId,
      );

      expect(list.statusCode, 200);
      final listResult = list.payload?['result'] as Map<String, dynamic>?;
      expect(listResult, isNotNull, reason: list.rawBody);
      expect(listResult!['tools'], isEmpty);
    });

    test('rejects a request with no token, echoing nothing', () async {
      final response = await _post(endpoint, _initializeBody());

      expect(response.statusCode, 401);
      expect(response.payload?['result'], isNull);
      expect(response.rawBody, isNot(contains(token)));
    });

    test('rejects a request with a wrong token', () async {
      final response = await _post(
        endpoint,
        _initializeBody(),
        token: 'not-the-token',
      );

      expect(response.statusCode, 401);
    });

    test('rejects a foreign Origin before dispatch', () async {
      final response = await _post(
        endpoint,
        _initializeBody(),
        token: token,
        origin: 'http://evil.example',
      );

      expect(response.statusCode, 403);
    });

    test('accepts a loopback Origin', () async {
      final response = await _post(
        endpoint,
        _initializeBody(),
        token: token,
        origin: 'http://localhost',
      );

      expect(response.statusCode, 200);
    });

    test('refuses GET: no server-initiated stream is offered', () async {
      final status = await _getStatus(endpoint, token: token);

      expect(status, 405);
    });

    test('never leaks the token through status or toString', () {
      final statusJson = jsonEncode(runtime.status.toJson());

      expect(statusJson, isNot(contains(token)));
      expect(runtime.status.toString(), isNot(contains(token)));
      expect(runtime.accessToken.toString(), isNot(contains(token)));
      expect(runtime.accessToken.authorizationHeader, 'Bearer $token');
    });

    test('stop releases the port', () async {
      await runtime.stop();

      await expectLater(
        _post(endpoint, _initializeBody(), token: token),
        throwsA(isA<SocketException>()),
      );
      expect(runtime.status.endpoint, isNull);
    });

    test('rotation needs a stopped runtime, then the old token dies', () async {
      await expectLater(
        runtime.rotateAccessToken(),
        throwsA(
          isA<ReleaseMcpException>().having(
            (error) => error.code,
            'code',
            ReleaseMcpErrorCode.invalidStateTransition,
          ),
        ),
      );

      await runtime.stop();
      final rotated = await runtime.rotateAccessToken();
      expect(rotated.value, isNot(token));

      final restarted = await runtime.start();
      final restartedEndpoint = restarted.endpoint!;

      final withOldToken = await _post(
        restartedEndpoint,
        _initializeBody(),
        token: token,
      );
      expect(withOldToken.statusCode, 401);

      final withNewToken = await _post(
        restartedEndpoint,
        _initializeBody(),
        token: rotated.value,
      );
      expect(withNewToken.statusCode, 200);
    });
  });

  group('ReleaseMcpRuntime.http port policy', () {
    test(
      'a taken port fails the start instead of rebinding elsewhere',
      () async {
        final first = ReleaseMcpRuntime.http(
          config: const ReleaseMcpConfig(port: 0),
        );
        addTearDown(first.dispose);
        final firstEndpoint = (await first.start()).endpoint!;

        final second = ReleaseMcpRuntime.http(
          config: ReleaseMcpConfig(port: firstEndpoint.port),
        );
        addTearDown(second.dispose);

        await expectLater(
          second.start(),
          throwsA(
            isA<ReleaseMcpException>().having(
              (error) => error.code,
              'code',
              ReleaseMcpErrorCode.transportStartFailed,
            ),
          ),
        );
        expect(second.state, ReleaseRuntimeState.error);
      },
    );
  });
}
