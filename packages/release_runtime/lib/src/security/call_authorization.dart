// packages/release_runtime/lib/src/security/call_authorization.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

import 'permissions.dart';

/// Asks the runtime whether a permission is held *right now*.
///
/// Not a snapshot of the grant set: a call can wait in a tool-owned queue long
/// enough for the user to withdraw consent, so the probe is consulted again
/// immediately before anything is dispatched.
typedef ReleaseGrantProbe = bool Function(ReleasePermissionId permission);

/// The authority one tool call carries from the transport down to the queue.
///
/// The runtime builds it per call with its current authorization epoch. A queued
/// operation re-checks [allows] before dispatch; a revocation, a stop, or a new
/// consent round invalidates the probe, so the operation is refused instead of
/// running under authority that no longer exists.
@immutable
final class ReleaseCallAuthorization {
  const ReleaseCallAuthorization({
    required this.epoch,
    this.grantProbe,
    this.sessionId,
  });

  /// Authorization that imposes no checks.
  ///
  /// For tests and for embedders that call a surface directly: the transport
  /// path always builds a real one.
  const ReleaseCallAuthorization.unchecked()
    : epoch = 0,
      grantProbe = null,
      sessionId = null;

  /// Authorization epoch the call started in.
  final int epoch;

  /// Live probe into the runtime's grant set; null means unchecked.
  final ReleaseGrantProbe? grantProbe;

  /// Transport session the call arrived on, when one is known.
  final String? sessionId;

  /// True when this authorization performs no checks.
  bool get isUnchecked => grantProbe == null;

  /// Whether [permission] may be exercised at this instant.
  bool allows(ReleasePermissionId? permission) {
    final probe = grantProbe;
    if (probe == null || permission == null) {
      return true;
    }
    return probe(permission);
  }
}
