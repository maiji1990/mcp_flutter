// showcase/flutter_release_demo/lib/main.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime): the fixture used to prove the
// release runtime on a real device.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:flutter_mcp_toolkit_release_flutter/flutter_mcp_toolkit_release_flutter.dart';

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

class _DemoScreenState extends State<DemoScreen> {
  final ReleaseSnapshotStore _store = ReleaseSnapshotStore();
  final TextEditingController _name = TextEditingController(text: 'Ada');
  ReleaseMcpRuntime? _runtime;
  String _status = 'off';
  String _endpoint = '-';
  bool _busy = false;
  int _count = 0;

  @override
  void dispose() {
    _name.dispose();
    unawaited(_shutdown());
    super.dispose();
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
      tools: ReleaseToolbox(<ReleaseToolSurface>[
        ReleaseReadTools(
          source: FlutterReleaseUiSnapshotSource(routeProvider: _routes),
          store: _store,
        ),
        ReleaseInteractionTools(
          store: _store,
          driver: const FlutterReleaseUiInteractionDriver(),
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
        ReleaseCaptureTools(
          source: FlutterReleaseUiCaptureSource(routeProvider: _routes),
          policy: const ReleaseCapturePolicy(
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
      body: const Center(child: Text('Card number 4111 1111 1111 1111')),
    );
  }
}
