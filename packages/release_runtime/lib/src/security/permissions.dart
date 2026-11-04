// packages/release_runtime/lib/src/security/permissions.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

import '../errors/release_mcp_error.dart';

/// A permission the session can hold.
///
/// Three fixed core permissions plus the `app:<name>` family, where each
/// registered business action declares its own permission. Instances are
/// canonical for core permissions, so `==` is identity for those.
@immutable
final class ReleasePermissionId {
  const ReleasePermissionId._(this.wireName);

  /// Read the UI tree, current page, and wait for changes.
  static const ReleasePermissionId uiRead = ReleasePermissionId._('ui:read');

  /// Click, type into, and scroll widgets.
  static const ReleasePermissionId uiInteract = ReleasePermissionId._(
    'ui:interact',
  );

  /// Capture a screenshot.
  static const ReleasePermissionId uiCapture = ReleasePermissionId._(
    'ui:capture',
  );

  /// The three permissions that exist without app registration.
  static const List<ReleasePermissionId> core = <ReleasePermissionId>[
    uiRead,
    uiInteract,
    uiCapture,
  ];

  static const String _appPrefix = 'app:';
  static final RegExp _appNamePattern = RegExp(r'^[a-z][a-z0-9._-]{0,63}$');

  /// Builds the per-action permission `app:<name>`.
  ///
  /// Names are restricted to lowercase slugs so a permission can never be
  /// confused with another namespace or smuggle control characters into logs.
  /// Throws [ReleaseMcpException] with `invalid_permission_id` for bad names.
  factory ReleasePermissionId.app(String name) {
    if (!_appNamePattern.hasMatch(name)) {
      throw ReleaseMcpException(
        ReleaseMcpErrorCode.invalidPermissionId,
        details: <String, Object?>{'permission': _appPrefix},
      );
    }
    return ReleasePermissionId._('$_appPrefix$name');
  }

  /// Parses a wire permission string, returning null when unrecognized.
  static ReleasePermissionId? tryParse(String value) {
    switch (value) {
      case 'ui:read':
        return uiRead;
      case 'ui:interact':
        return uiInteract;
      case 'ui:capture':
        return uiCapture;
    }

    if (!value.startsWith(_appPrefix)) {
      return null;
    }

    final name = value.substring(_appPrefix.length);
    if (!_appNamePattern.hasMatch(name)) {
      return null;
    }
    return ReleasePermissionId._(value);
  }

  /// Parses a wire permission string.
  ///
  /// Throws [ReleaseMcpException] with `invalid_permission_id` when
  /// unrecognized.
  static ReleasePermissionId parse(String value) {
    final parsed = tryParse(value);
    if (parsed == null) {
      throw ReleaseMcpException(
        ReleaseMcpErrorCode.invalidPermissionId,
        details: <String, Object?>{'permission': _describeForError(value)},
      );
    }
    return parsed;
  }

  // Echoes at most the namespace, never the whole untrusted string.
  static String _describeForError(String value) {
    final separator = value.indexOf(':');
    return separator <= 0 ? 'unknown' : value.substring(0, separator);
  }

  /// Wire name, for example `ui:read` or `app:pay.invoice`.
  final String wireName;

  /// True for the `app:<name>` family.
  bool get isAppPermission => wireName.startsWith(_appPrefix);

  /// Registered action name, when [isAppPermission].
  String? get appName =>
      isAppPermission ? wireName.substring(_appPrefix.length) : null;

  /// True for permissions that let a session change app state or read pixels.
  bool get isSensitive =>
      this == uiInteract || this == uiCapture || isAppPermission;

  @override
  bool operator ==(Object other) =>
      other is ReleasePermissionId && other.wireName == wireName;

  @override
  int get hashCode => wireName.hashCode;

  @override
  String toString() => wireName;
}

/// Immutable set of [ReleasePermissionId]s.
@immutable
final class ReleasePermissionSet {
  ReleasePermissionSet(Iterable<ReleasePermissionId> permissions)
    : _permissions = Set<ReleasePermissionId>.unmodifiable(permissions);

  /// The empty set.
  static final ReleasePermissionSet empty = ReleasePermissionSet(
    const <ReleasePermissionId>[],
  );

  /// `{ui:read}`, the baseline every session gets by starting.
  static final ReleasePermissionSet readOnlyBase = ReleasePermissionSet(
    const <ReleasePermissionId>[ReleasePermissionId.uiRead],
  );

  final Set<ReleasePermissionId> _permissions;

  /// Unmodifiable view of the members.
  Set<ReleasePermissionId> get ids => _permissions;

  /// True when nothing is held.
  bool get isEmpty => _permissions.isEmpty;

  /// True when at least one permission is held.
  bool get isNotEmpty => _permissions.isNotEmpty;

  /// Number of held permissions.
  int get length => _permissions.length;

  /// Whether [id] is held.
  bool contains(ReleasePermissionId id) => _permissions.contains(id);

  /// True when no interactive, capture, or app permission is held.
  bool get isReadOnly => !_permissions.any((id) => id.isSensitive);

  /// Set union.
  ReleasePermissionSet union(ReleasePermissionSet other) =>
      ReleasePermissionSet(<ReleasePermissionId>{
        ..._permissions,
        ...other._permissions,
      });

  /// Set difference.
  ReleasePermissionSet difference(ReleasePermissionSet other) =>
      ReleasePermissionSet(_permissions.difference(other._permissions));

  /// Sorted wire names, for stable JSON and stable tests.
  List<String> toWireList() {
    final names = _permissions.map((id) => id.wireName).toList()..sort();
    return List<String>.unmodifiable(names);
  }

  @override
  bool operator ==(Object other) =>
      other is ReleasePermissionSet &&
      other._permissions.length == _permissions.length &&
      other._permissions.containsAll(_permissions);

  @override
  int get hashCode => Object.hashAllUnordered(_permissions);

  @override
  String toString() => 'ReleasePermissionSet(${toWireList().join(', ')})';
}

/// Explicit user consent handed to `ReleaseMcpRuntime.start()`.
///
/// The runtime never invents consent: `ui:interact`, `ui:capture`, and every
/// `app:<name>` permission take effect only when listed here (or granted later
/// through `grantPermissions`).
@immutable
final class ReleaseStartAuthorization {
  ReleaseStartAuthorization({
    Iterable<ReleasePermissionId> grantedPermissions =
        const <ReleasePermissionId>[],
    this.reason,
    this.issuedAt,
  }) : grantedPermissions = ReleasePermissionSet(grantedPermissions);

  /// Read-only consent: the caller explicitly allows the read surface only.
  ReleaseStartAuthorization.readOnly({this.reason, this.issuedAt})
    : grantedPermissions = ReleasePermissionSet.readOnlyBase;

  /// Permissions the user approved for this session.
  final ReleasePermissionSet grantedPermissions;

  /// Why consent was granted, for the audit trail. Never contains user data.
  final String? reason;

  /// When consent was collected.
  final DateTime? issuedAt;

  /// Redaction-safe JSON view.
  Map<String, Object?> toJson() => <String, Object?>{
    'grantedPermissions': grantedPermissions.toWireList(),
    'reason': reason,
    'issuedAt': issuedAt?.toIso8601String(),
  };
}
