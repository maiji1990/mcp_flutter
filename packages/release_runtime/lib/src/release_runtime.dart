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
import 'security/access_token.dart';
import 'security/audit.dart';
import 'security/call_authorization.dart';
import 'security/permissions.dart';
import 'security/rate_limiter.dart';
import 'server/http_transport.dart';
import 'tools/release_tools.dart';
import 'transport/runtime_transport.dart';

/// Opt-in MCP runtime for shipped Flutter apps.
///
/// Responsibilities: configuration, lifecycle, consent, bearer
/// authentication, and the transport seam. The tool catalog, semantic
/// snapshots, and guarded interactions arrive in the follow-up PRs described in
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
/// - Every request must present [accessToken]; nothing is served without it.
final class ReleaseMcpRuntime {
  ReleaseMcpRuntime({
    this.config = const ReleaseMcpConfig(),
    ReleaseRuntimeTransport? transport,
    ReleaseAccessToken? accessToken,
    ReleaseToolSurface? tools,
    this.rateLimit = const ReleaseRateLimit(),
    this.auditSink,
  }) : _transport = transport ?? const InertRuntimeTransport(),
       _accessToken = accessToken ?? ReleaseAccessToken.generate(),
       // Kept private on purpose: a public field would let a caller invoke the
       // surface directly and skip the permission checks in
       // _GuardedToolSurface.
       // ignore: prefer_initializing_formals
       _tools = tools {
    _lifecycle = ReleaseRuntimeLifecycle();
    _rateLimiter = ReleaseRateLimiter(rateLimit);
  }

  /// Runtime backed by the Streamable HTTP transport.
  ///
  /// This is the release-ready shape: a loopback HTTP MCP endpoint with bearer
  /// authentication, Origin validation, and request bounds taken from [config].
  /// Nothing listens until [start] is called.
  factory ReleaseMcpRuntime.http({
    ReleaseMcpConfig config = const ReleaseMcpConfig(),
    ReleaseAccessToken? accessToken,
    ReleaseToolSurface? tools,
    ReleaseRateLimit rateLimit = const ReleaseRateLimit(),
    ReleaseAuditSink? auditSink,
  }) => ReleaseMcpRuntime(
    config: config,
    transport: HttpReleaseRuntimeTransport(),
    accessToken: accessToken,
    tools: tools,
    rateLimit: rateLimit,
    auditSink: auditSink,
  );

  /// Configuration the runtime was built with.
  final ReleaseMcpConfig config;

  /// Sliding-window budget applied to every tool call.
  final ReleaseRateLimit rateLimit;

  /// Optional redaction-safe audit sink; exceptions from it are swallowed.
  final ReleaseAuditSink? auditSink;

  late final ReleaseRateLimiter _rateLimiter;

  final ReleaseRuntimeTransport _transport;
  final ReleaseToolSurface? _tools;
  ReleaseAccessToken _accessToken;
  late final ReleaseRuntimeLifecycle _lifecycle;
  final StreamController<ReleaseRuntimeStatus> _statusChanges =
      StreamController<ReleaseRuntimeStatus>.broadcast();

  ReleasePermissionSet _granted = ReleasePermissionSet.empty;
  int _toolRequests = 0;

  /// Bumped by every consent and lifecycle change. A tool call carries the
  /// epoch it started in; work that waited in a queue is refused once the epoch
  /// moved, because its authority belongs to a session that no longer exists.
  int _epoch = 0;
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

  /// The bearer secret a client must present.
  ///
  /// Surface it to the user (a pairing code in your settings screen) and hand
  /// it to the client out of band. Its `toString` is redacted, but the `value`
  /// is the secret: do not log it, and never put it in a URL.
  ReleaseAccessToken get accessToken => _accessToken;

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
          maxSessions: config.maxSessions,
          sessionIdleTimeout: config.sessionIdleTimeout,
          accessToken: _accessToken.value,
          toolSurface: _tools == null
              ? null
              : _GuardedToolSurface(this, _tools),
        ),
      );

      _epoch += 1;
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
    _epoch += 1;
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
    _epoch += 1;
    _emitStatus();
    return status;
  });

  /// Issues a new [accessToken].
  ///
  /// Only while stopped: the transport captured the previous token when it
  /// bound, so rotation is `stop()` → `rotateAccessToken()` → `start()`. The
  /// alternative — rebinding under a live client — would either keep the old
  /// secret alive or silently break the endpoint. Throws
  /// `invalid_state_transition` while starting, running, or stopping.
  Future<ReleaseAccessToken> rotateAccessToken() => _serialize(() async {
    _ensureNotDisposed();
    if (_lifecycle.state != ReleaseRuntimeState.disabled) {
      throw ReleaseMcpException(
        ReleaseMcpErrorCode.invalidStateTransition,
        details: <String, Object?>{'reason': 'rotation_requires_stopped'},
      );
    }
    _accessToken = ReleaseAccessToken.generate();
    _emitStatus();
    return _accessToken;
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
    _epoch += 1;
    _rateLimiter.reset();
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

/// Wraps a [ReleaseToolSurface] with the runtime's own rules.
///
/// The transport never sees the raw surface: state, permission, and error
/// mapping happen here, so every transport (HTTP today, anything later)
/// inherits them. Nothing a tool handler throws escapes as a stack trace — it
/// becomes `unknown_error` plus the exception *type*.
final class _GuardedToolSurface implements ReleaseToolSurface {
  _GuardedToolSurface(this._runtime, this._inner);

  final ReleaseMcpRuntime _runtime;
  final ReleaseToolSurface _inner;

  /// Calls currently dispatched, across all sessions.
  int _active = 0;

  /// Calls admitted but waiting for a slot, in arrival order.
  final List<Completer<void>> _waiting = <Completer<void>>[];

  /// Hard ceiling on queued calls, so a flood is refused rather than buffered
  /// without bound (NET-01).
  static const int _maxWaiting = 16;

  @override
  List<ReleaseToolDefinition> get tools => _inner.tools;

  @override
  Future<ReleaseToolCallResult> call(
    String name,
    Map<String, Object?> arguments, {
    ReleaseCallAuthorization? authorization,
  }) async {
    if (_runtime._lifecycle.state != ReleaseRuntimeState.running) {
      return _refusal(ReleaseMcpErrorCode.runtimeNotRunning);
    }

    ReleaseToolDefinition? definition;
    for (final tool in _inner.tools) {
      if (tool.name == name) {
        definition = tool;
        break;
      }
    }
    if (definition == null) {
      return _refusal(ReleaseMcpErrorCode.toolNotFound);
    }

    final epoch = _runtime._epoch;
    final authority = ReleaseCallAuthorization(
      epoch: epoch,
      grantProbe: (permission) =>
          _runtime._lifecycle.state == ReleaseRuntimeState.running &&
          _runtime._epoch == epoch &&
          _runtime._granted.contains(permission),
    );

    final requiredPermission = definition.permissionFor(arguments);
    if (requiredPermission != null && !authority.allows(requiredPermission)) {
      _record(
        name,
        requiredPermission,
        allowed: false,
        reason: ReleaseMcpErrorCode.permissionDenied,
        epoch: epoch,
        arguments: arguments,
      );
      return _refusal(
        ReleaseMcpErrorCode.permissionDenied,
        details: <String, Object?>{'permission': requiredPermission.wireName},
      );
    }

    if (!_runtime._rateLimiter.allow()) {
      _record(
        name,
        requiredPermission,
        allowed: false,
        reason: ReleaseMcpErrorCode.rateLimited,
        epoch: epoch,
        arguments: arguments,
      );
      return _refusal(
        ReleaseMcpErrorCode.rateLimited,
        details: <String, Object?>{
          'limit': _runtime.rateLimit.maxRequests,
          'windowMs': _runtime.rateLimit.window.inMilliseconds,
        },
      );
    }

    final admits = await _acquire();
    if (!admits) {
      return _refusal(
        ReleaseMcpErrorCode.serverBusy,
        details: <String, Object?>{
          'maxConcurrent': _runtime.config.maxConcurrentRequests,
        },
      );
    }

    // The call may have waited for a slot for a while. Re-check the state and
    // the grant after admission, so a stop or a revocation that happened while
    // it queued refuses it instead of letting it run under old authority.
    if (_runtime._lifecycle.state != ReleaseRuntimeState.running) {
      _release();
      _record(
        name,
        requiredPermission,
        allowed: false,
        reason: ReleaseMcpErrorCode.runtimeNotRunning,
        epoch: epoch,
        arguments: arguments,
      );
      return _refusal(ReleaseMcpErrorCode.runtimeNotRunning);
    }
    if (requiredPermission != null && !authority.allows(requiredPermission)) {
      _release();
      _record(
        name,
        requiredPermission,
        allowed: false,
        reason: 'authorization_changed',
        epoch: epoch,
        arguments: arguments,
      );
      return _refusal(
        ReleaseMcpErrorCode.permissionDenied,
        details: <String, Object?>{
          'permission': requiredPermission.wireName,
          'reason': 'authorization_changed',
        },
      );
    }

    try {
      final result = await _inner.call(
        name,
        arguments,
        authorization: authorization ?? authority,
      );
      _record(
        name,
        requiredPermission,
        allowed: result.success,
        reason: result.error?.code,
        epoch: epoch,
        arguments: arguments,
      );
      return result;
    } catch (error) {
      return _refusal(
        ReleaseMcpErrorCode.unknown,
        details: <String, Object?>{'cause': error.runtimeType.toString()},
      );
    } finally {
      _release();
    }
  }

  /// Takes a dispatch slot, waiting when the budget is full.
  ///
  /// Returns false when the queue is already at [_maxWaiting].
  Future<bool> _acquire() {
    final limit = _runtime.config.maxConcurrentRequests;
    if (_active < limit) {
      _active += 1;
      return Future<bool>.value(true);
    }
    if (_waiting.length >= _maxWaiting) {
      return Future<bool>.value(false);
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    return completer.future.then((_) => true);
  }

  /// Hands the slot to the next waiter, or gives it back.
  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _active -= 1;
    }
  }

  /// Emits a redaction-safe audit record; sink failures are swallowed.
  void _record(
    String tool,
    ReleasePermissionId? permission, {
    required bool allowed,
    String? reason,
    required int epoch,
    required Map<String, Object?> arguments,
  }) {
    final sink = _runtime.auditSink;
    if (sink == null) {
      return;
    }
    try {
      sink(
        ReleaseAuditEvent(
          tool: tool,
          allowed: allowed,
          at: DateTime.now(),
          permission: permission?.wireName,
          reason: reason,
          argumentKeys: arguments.keys.take(16).toList(growable: false),
          epoch: epoch,
        ),
      );
    } on Object {
      // Auditing must never break a call.
    }
  }

  ReleaseToolCallResult _refusal(
    String code, {
    Map<String, Object?> details = const <String, Object?>{},
  }) => ReleaseToolCallResult(
    requestId: 'req_${++_runtime._toolRequests}',
    success: false,
    error: ReleaseToolError(
      code,
      descriptorForReleaseErrorCode(code).message,
      details: details,
    ),
  );
}
