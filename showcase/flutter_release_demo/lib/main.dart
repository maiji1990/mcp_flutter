// showcase/flutter_release_demo/lib/main.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime): the fixture used to prove the
// release runtime on a real device.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:flutter_mcp_toolkit_release_flutter/flutter_mcp_toolkit_release_flutter.dart';
import 'package:flutter_mcp_toolkit_release_webview/flutter_mcp_toolkit_release_webview.dart';

import 'web_demo_screen.dart';

void main() {
  runApp(const ReleaseDemoApp());
}

/// Records the route the app is showing, so the runtime can report it and the
/// capture policy can block screens.
final class RouteWatcher extends NavigatorObserver {
  String _current = '/';

  /// Route name the app is on.
  String get current => _current;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) {
      _current = name;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = previousRoute?.settings.name;
    if (name != null) {
      _current = name;
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final name = newRoute?.settings.name;
    if (name != null) {
      _current = name;
    }
  }
}

final RouteWatcher _routeWatcher = RouteWatcher();

class ReleaseDemoApp extends StatelessWidget {
  const ReleaseDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Release MCP Demo',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      navigatorObservers: <NavigatorObserver>[_routeWatcher],
      home: const DemoScreen(),
    );
  }
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> with WidgetsBindingObserver {
  final ReleaseSnapshotStore _store = ReleaseSnapshotStore();
  final ReleaseWebViewRegistry _webRegistry = ReleaseWebViewRegistry();
  final TextEditingController _name = TextEditingController(text: 'Ada');
  ReleaseMcpRuntime? _runtime;
  String _status = 'off';
  String _endpoint = '-';
  bool _busy = false;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    unawaited(_shutdown());
    super.dispose();
  }

  /// A phone that is no longer in front must not keep an agent endpoint open:
  /// the release runtime is a foreground capability (LIFE-01).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      return;
    }
    final runtime = _runtime;
    if (runtime == null) {
      return;
    }
    unawaited(
      runtime.stop().whenComplete(() {
        if (!mounted) {
          return;
        }
        setState(() {
          _runtime = null;
          _status = 'paused (app in background)';
          _endpoint = '-';
        });
      }),
    );
  }

  ReleaseRouteProvider get _routes =>
      CallbackReleaseRouteProvider(() async => _routeWatcher.current);

  Future<void> _shutdown() async {
    final runtime = _runtime;
    _runtime = null;
    await runtime?.dispose();
  }

  Future<void> _enable() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final runtime = ReleaseMcpRuntime.http(
      config: const ReleaseMcpConfig(port: 8765, endpoint: '/mcp'),
      // A local client should not be able to hammer the UI; 120 calls/minute is
      // generous for an agent and still bounded.
      rateLimit: const ReleaseRateLimit(maxRequests: 120),
      // Logcat carries the audit trail for the device run. Event payloads hold
      // tool names and argument keys only, never values.
      auditSink: (event) =>
          debugPrint('release-mcp audit ${jsonEncode(event.toJson())}'),
      tools: ReleaseToolbox(<ReleaseToolSurface>[
        ReleaseReadTools(
          source: FlutterReleaseUiSnapshotSource(routeProvider: _routes),
          store: _store,
          // /wallet is never readable, whatever the client was granted. The
          // route provider always answers, so "unknown" means the app moved to
          // a page it cannot name — refuse rather than guess.
          privacy: const RedactingPrivacyFilter(
            policy: ReleaseUiPrivacyPolicy(
              deniedRoutes: <String>{'/wallet'},
              denyWhenRouteUnknown: true,
            ),
          ),
        ),
        ReleaseInteractionTools(
          store: _store,
          driver: FlutterReleaseUiInteractionDriver(routeProvider: _routes),
        ),
        ReleaseAppActionTools(<ReleaseAppAction>[
          ReleaseAppAction(
            name: 'demo.increment',
            description: 'Increment the on-screen counter',
            handler: (arguments) async {
              if (!mounted) {
                return <String, Object?>{'count': _count};
              }
              setState(() => _count += 1);
              return <String, Object?>{'count': _count};
            },
          ),
        ]),
        ReleaseWebTools(
          source: WebViewDomReleaseSource(_webRegistry),
          // The demo's H5 fixture is served from loopback over HTTP, so the
          // staging opt-in is explicit here; production pages are HTTPS.
          policy: const ReleaseWebPrivacyPolicy(allowInsecureHttp: true),
        ),
        ReleaseCaptureTools(
          source: FlutterReleaseUiCaptureSource(routeProvider: _routes),
          // Screenshots are opt-in per route: only the home screen, and never
          // the wallet even though the home allow-list would not match it.
          policy: const ReleaseCapturePolicy(
            // `/web-demo` is allowed so the fixture can prove what a hybrid
            // (platform-view) screenshot actually contains; `/wallet` stays
            // blocked.
            allowedRoutes: <String>{'/', '/web-demo'},
            blockedRoutes: <String>{'/wallet'},
          ),
        ),
      ]),
    );

    try {
      await runtime.start(
        authorization: ReleaseStartAuthorization.readOnly(
          reason: 'user enabled local AI access',
        ),
      );
      if (!mounted) {
        await runtime.dispose();
        return;
      }
      setState(() {
        _runtime = runtime;
        _status = runtime.state.wireName;
        _endpoint = runtime.status.endpoint?.toString() ?? '-';
      });
    } on ReleaseMcpException catch (error) {
      await runtime.dispose();
      if (!mounted) {
        return;
      }
      setState(() => _status = 'error: ${error.code}');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _disable() async {
    final runtime = _runtime;
    setState(() {
      _runtime = null;
      _status = 'off';
      _endpoint = '-';
    });
    await runtime?.dispose();
  }

  Future<void> _grant(List<ReleasePermissionId> permissions) async {
    final runtime = _runtime;
    if (runtime == null) {
      return;
    }
    await runtime.grantPermissions(permissions);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;
    return Scaffold(
      appBar: AppBar(title: const Text('Release MCP Demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SwitchListTile(
            title: const Text('Allow local AI access'),
            subtitle: Text('Status: $_status'),
            value: runtime != null,
            onChanged: (value) => value ? _enable() : _disable(),
          ),
          if (runtime != null) ...<Widget>[
            Text('Endpoint: $_endpoint'),
            const Text('Pairing token (bearer):'),
            SelectableText(
              runtime.accessToken.value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: () => _grant(<ReleasePermissionId>[
                    ReleasePermissionId.uiInteract,
                  ]),
                  child: const Text('Grant interactions'),
                ),
                FilledButton.tonal(
                  onPressed: () => _grant(<ReleasePermissionId>[
                    ReleasePermissionId.uiCapture,
                  ]),
                  child: const Text('Grant capture'),
                ),
                FilledButton.tonal(
                  onPressed: () => _grant(<ReleasePermissionId>[
                    ReleasePermissionId.uiInteract,
                    ReleasePermissionId.uiCapture,
                    ReleasePermissionId.webRead,
                    ReleasePermissionId.webInteract,
                    ReleasePermissionId.app('demo.increment'),
                  ]),
                  child: const Text('Grant all'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Granted: '
                '${runtime.status.grantedPermissions.toWireList().join(', ')}',
              ),
            ),
          ],
          const Divider(height: 32),
          Text(
            'Counter: $_count',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => setState(() => _count += 1),
            child: const Text('Increment'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Your name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/wallet'),
                builder: (context) => const WalletScreen(),
              ),
            ),
            child: const Text('Open secret screen'),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/web-demo'),
                builder: (context) => WebDemoScreen(registry: _webRegistry),
              ),
            ),
            child: const Text('Open WebView demo'),
          ),
          const Divider(height: 32),
          const Text('Scrollable list'),
          SizedBox(
            height: 320,
            child: ListView.builder(
              itemCount: 40,
              itemBuilder: (context, index) =>
                  ListTile(dense: true, title: Text('Row $index')),
            ),
          ),
        ],
      ),
    );
  }
}

/// A screen the capture policy blocks: proof that pixels are refused per route.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      // Two layers on purpose: the route is denied for reads, and the text is
      // marked sensitive in case the screen is ever reachable another way.
      body: const Center(
        child: AgentSensitive(child: Text('Card number 4111 1111 1111 1111')),
      ),
    );
  }
}
