// packages/release_runtime/lib/src/release_runtime.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'dart:async';

import 'config/release_mcp_config.dart';
import 'errors/release_mcp_error.dart';
import 'lifecycle/runtime_lifecycle.dart';
import 'lifecycle/runtime_status.dart';
import 'security/permissions.dart';
import 'transport/runtime_transport.dart';

/// Opt-in MCP runtime for shipped Flutter apps.
///
/// Responsibilities in this PR: configuration, lifecycle, consent, and the
/// transport seam. No MCP tools, no HTTP, no VM Service, no Dart eval: those
/// arrive in the follow-up PRs described in
/// `docs/release_runtime/README.md`.
///
/// Guarantees:
/// - Constructing a runtime starts nothing and binds nothing.
/// - `start`, `stop`, and `dispose` are idempotent and serialized: concurrent
///   calls never interleave a transport handoff.
/// - Failures surface as [ReleaseMcpException] with a stable
///   [ReleaseMcpErrorCode]; the state machine records the same code in
///   [ReleaseRuntimeStatus.errorCode].
/// - A session is read-only unless the caller passes explicit
///   [ReleaseStartAuthorization] grants.
final class ReleaseMcpRuntime {
  ReleaseMcpRuntime({
    this.config = const ReleaseMcpConfig(),
    ReleaseRuntimeTransport? transport,
  }) : _transport = transport ?? const InertRuntimeTransport() {
    _lifecycle = ReleaseRuntimeLifecycle();
  }

  /// Configuration the runtime was built with.
  final ReleaseMcpConfig config;

  final ReleaseRuntimeTransport _transport;
  late final ReleaseRuntimeLifecycle _lifecycle;
  final StreamController<ReleaseRuntimeStatus> _statusChanges =
      StreamController<ReleaseRuntimeStatus>.broadcast();

  ReleasePermissionSet _granted = ReleasePermissionSet.empty;
  Uri? _endpoint;
  DateTime? _startedAt;
  bool _disposed = false;

  /// Serializes lifecycle mutations. Errors never poison the queue.
  Future<void> _tail = Future<void>.value();

  /// Current lifecycle state.
  ReleaseRuntimeState get state => _lifecycle.state;

  /// Broadcast stream of lifecycle states.
  Stream<ReleaseRuntimeState> get stateChanges => _lifecycle.changes;

  /// True once [dispose] has run.
  bool get isDisposed => _disposed;

  /// Read-only snapshot of the runtime.
  ReleaseRuntimeStatus get status => ReleaseRuntimeStatus(
    state: _lifecycle.state,
    isDisposed: _disposed,
    isReadOnly: _granted.isReadOnly,
    grantedPermissions: _granted,
    config: config,
    endpoint: _endpoint,
    startedAt: _startedAt,
    errorCode: _lifecycle.errorCode,
  );

  /// Broadcast stream of status snapshots, emitted after every change.
  Stream<ReleaseRuntimeStatus> get statusChanges => _statusChanges.stream;

  /// Starts serving.
  ///
  /// Idempotent: calling it while already running returns the current status
  /// without touching the transport.
  ///
  /// [authorization] carries the user's consent. Omit it for a read-only
  /// session when [ReleaseMcpConfig.readOnlyByDefault] is true; when that flag
  /// is false, omitting it fails with `authorization_missing` instead of
  /// silently degrading to read-only.
  ///
  /// Throws [ReleaseMcpException] with `invalid_config`,
  /// `authorization_missing`, `runtime_disposed`, or
  /// `transport_start_failed`.
  Future<ReleaseRuntimeStatus> start({
    ReleaseStartAuthorization? authorization,
  }) => _serialize(() async {
    _ensureNotDisposed();

    if (_lifecycle.state == ReleaseRuntimeState.running) {
      return status;
    }

    final problems = config.validate();
    if (problems.isNotEmpty) {
      throw ReleaseMcpException.invalidConfig(problems);
    }

    final requested =
        authorization?.grantedPermissions ?? ReleasePermissionSet.empty;
    final mustAuthorize = !config.readOnlyByDefault && authorization == null;
    if (mustAuthorize) {
      throw ReleaseMcpException(ReleaseMcpErrorCode.authorizationMissing);
    }

    // Starting always grants read; everything else needs explicit consent.
    final effective = ReleasePermissionSet.readOnlyBase.union(requested);

    _lifecycle.transitionTo(ReleaseRuntimeState.starting);
    _emitStatus();

    try {
      final endpoint = await _transport.start(
        ReleaseTransportStartRequest(
          host: config.host,
          port: config.port,
          endpoint: config.endpoint,
          requestTimeout: config.requestTimeout,
          maxRequestBytes: config.maxRequestBytes,
          maxConcurrentRequests: config.maxConcurrentRequests,
        ),
      );

      _granted = effective;
      _endpoint = endpoint;
      _startedAt = DateTime.now().toUtc();
      _lifecycle.transitionTo(ReleaseRuntimeState.running);
      _emitStatus();
      return status;
    } catch (error) {
      _resetSession();
      if (_lifecycle.state != ReleaseRuntimeState.error) {
        _lifecycle.fail(ReleaseMcpErrorCode.transportStartFailed);
      }
      _emitStatus();
      if (error is ReleaseMcpException) {
        rethrow;
      }
      throw ReleaseMcpException(
        ReleaseMcpErrorCode.transportStartFailed,
        details: <String, Object?>{'cause': error.runtimeType.toString()},
      );
    }
  });

  /// Stops serving and releases the endpoint.
  ///
  /// Idempotent: calling it while disabled returns the current status. Safe to
  /// call from `error`.
  Future<ReleaseRuntimeStatus> stop() => _serialize(() async {
    if (_disposed) {
      return status;
    }

    final current = _lifecycle.state;
    if (current == ReleaseRuntimeState.disabled) {
      return status;
    }

    _lifecycle.transitionTo(ReleaseRuntimeState.stopping);
    _emitStatus();

    try {
      await _transport.stop();
    } catch (error) {
      _lifecycle.fail(ReleaseMcpErrorCode.transportStopFailed);
      _emitStatus();
      throw ReleaseMcpException(
        ReleaseMcpErrorCode.transportStopFailed,
        details: <String, Object?>{'cause': error.runtimeType.toString()},
      );
    }

    _resetSession();
    _lifecycle.transitionTo(ReleaseRuntimeState.disabled);
    _emitStatus();
    return status;
  });

  /// Adds consent to the running session.
  ///
  /// Takes effect immediately; in-flight tool calls are not retroactively
  /// granted anything. Throws `runtime_not_running` when not serving.
  Future<ReleaseRuntimeStatus> grantPermissions(
    Iterable<ReleasePermissionId> permissions,
  ) => _serialize(() async {
    _ensureNotDisposed();
    _requireRunning();
    _granted = _granted.union(ReleasePermissionSet(permissions));
    _emitStatus();
    return status;
  });

  /// Withdraws consent from the running session.
  ///
  /// `ui:read` is structural (a serving session always exposes reads), so it
  /// stays granted; stop the runtime to end the session instead.
  Future<ReleaseRuntimeStatus> revokePermissions(
    Iterable<ReleasePermissionId> permissions,
  ) => _serialize(() async {
    _ensureNotDisposed();
    _requireRunning();
    final revoked = ReleasePermissionSet(permissions)
        .difference(ReleasePermissionSet.readOnlyBase);
    _granted = _granted.difference(revoked);
    _emitStatus();
    return status;
  });

  /// Tears the runtime down, releasing the transport and closing streams.
  ///
  /// Idempotent. Never throws: a transport that fails to stop is recorded in
  /// the final status instead, because dispose runs from app teardown paths
  /// where throwing would mask the original reason.
  Future<void> dispose() => _serialize(() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    if (_lifecycle.state != ReleaseRuntimeState.disabled) {
      try {
        await _transport.stop();
      } catch (_) {
        // Dispose never throws; see the doc comment.
      }
      _resetSession();
      _lifecycle.transitionTo(ReleaseRuntimeState.disabled);
    }

    _emitStatus();
    await _lifecycle.close();
    await _statusChanges.close();
  });

  void _ensureNotDisposed() {
    if (_disposed) {
      throw ReleaseMcpException(ReleaseMcpErrorCode.runtimeDisposed);
    }
  }

  void _requireRunning() {
    if (_lifecycle.state != ReleaseRuntimeState.running) {
      throw ReleaseMcpException(ReleaseMcpErrorCode.runtimeNotRunning);
    }
  }

  void _resetSession() {
    _granted = ReleasePermissionSet.empty;
    _endpoint = null;
    _startedAt = null;
  }

  void _emitStatus() {
    if (!_statusChanges.isClosed) {
      _statusChanges.add(status);
    }
  }

  /// Runs [action] after every previously queued mutation finished.
  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }
}
