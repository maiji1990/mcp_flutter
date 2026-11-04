// showcase/flutter_release_demo/lib/web_demo_screen.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0): a real WebView fixture.
//
// The page is served by the app itself on 127.0.0.1, so the device test needs
// no network and the origin allow-list is exact. Cleartext is permitted for
// loopback only (android/app/src/main/res/xml/network_security_config.xml).
//
// The fixture covers four cases the unit tests cannot: a SPA History
// navigation, a cross-origin iframe (localhost is a different host than
// 127.0.0.1, so it is a different origin), a framework-style controlled input,
// and a platform-view screen for hybrid capture checks.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:flutter_mcp_toolkit_release_webview/flutter_mcp_toolkit_release_webview.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _webDemoHtmlTemplate = '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Orders H5</title>
  <style>
    body { font-family: sans-serif; margin: 18px; }
    input, button { font-size: 17px; padding: 9px; margin: 5px 0; width: 100%; }
    li { font-size: 17px; margin: 5px 0; }
    iframe { border: 1px solid #999; }
  </style>
</head>
<body>
  <h1>Order search</h1>
  <label for="q">Search orders</label>
  <input id="q" name="q" aria-label="Search orders" autocomplete="off">
  <button id="go" aria-label="Search">Search</button>
  <ul id="results"></ul>

  <h2>Controlled input</h2>
  <label for="note">Controlled note</label>
  <input id="note" name="note" aria-label="Controlled note" autocomplete="off">
  <div id="model" role="status" aria-label="Model: empty">Model: empty</div>

  <h2>SPA</h2>
  <button id="details" aria-label="Open details">Open details</button>
  <div id="spa"></div>

  <h2>Cross-origin iframe</h2>
  <iframe id="frame" sandbox="allow-scripts" width="220" height="90"
    srcdoc="<button aria-label='Inside frame'>Inside frame</button>"></iframe>

  <label for="pin">PIN</label>
  <input id="pin" name="pin" type="password" aria-label="PIN" value="1234">

  <script>
    // A framework-style controlled input: the view is a function of state.
    var state = { note: '' };
    function renderModel() {
      var label = 'Model: ' + (state.note || 'empty');
      var node = document.getElementById('model');
      node.textContent = label;
      node.setAttribute('aria-label', label);
    }
    document.getElementById('note').addEventListener('input', function (event) {
      state.note = event.target.value;
      renderModel();
    });
    document.getElementById('note').addEventListener('change', function (event) {
      state.note = event.target.value;
      renderModel();
    });
    renderModel();

    document.getElementById('go').addEventListener('click', function () {
      var value = document.getElementById('q').value;
      var list = document.getElementById('results');
      list.innerHTML = '';
      var item = document.createElement('li');
      item.textContent = 'Result for ' + value;
      item.setAttribute('role', 'status');
      item.setAttribute('aria-label', item.textContent);
      list.appendChild(item);
    });

    document.getElementById('details').addEventListener('click', function () {
      history.pushState({ page: 'details' }, '', '/details');
      document.getElementById('spa').innerHTML =
        '<div role="status" aria-label="Details page">Details page</div>';
    });
  </script>
</body>
</html>
''';

/// Hosts a WebView with a locally served page and registers it for the runtime.
class WebDemoScreen extends StatefulWidget {
  const WebDemoScreen({super.key, required this.registry});

  /// The registry the runtime's web tools read from.
  final ReleaseWebViewRegistry registry;

  @override
  State<WebDemoScreen> createState() => _WebDemoScreenState();
}

class _WebDemoScreenState extends State<WebDemoScreen> {
  HttpServer? _server;
  WebViewController? _controller;
  ReleaseWebViewRegistration? _registration;
  String _origin = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_webDemoHtmlTemplate);
        await request.response.close();
      });

      final origin = 'http://127.0.0.1:${server.port}';
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);
      final registration = widget.registry.register(
        viewId: 'order-h5',
        engine: WebViewFlutterEngine(controller),
        allowedOrigins: <String>{origin},
        allowHttp: true,
        privacyPolicy: const ReleaseWebPrivacyPolicy(
          allowInsecureHttp: true,
          deniedPathPrefixes: <String>{'/account'},
        ),
      );
      await controller.loadRequest(Uri.parse('$origin/'));
      if (!mounted) {
        widget.registry.unregister('order-h5');
        await server.close(force: true);
        return;
      }
      setState(() {
        _origin = origin;
        _controller = controller;
        _registration = registration;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.runtimeType.toString());
      }
    }
  }

  @override
  void dispose() {
    final registration = _registration;
    if (registration != null) {
      widget.registry.unregister(registration.viewId);
    }
    _server?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('WebView demo')),
      body: _error != null
          ? Center(child: Text('WebView fixture failed: $_error'))
          : controller == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('origin: $_origin'),
                ),
                Expanded(child: WebViewWidget(controller: controller)),
              ],
            ),
    );
  }
}
