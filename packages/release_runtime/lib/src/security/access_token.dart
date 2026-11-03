// packages/release_runtime/lib/src/security/access_token.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The shared secret an MCP client presents as `Authorization: Bearer …`.
///
/// Generated from a cryptographically secure random source, kept in memory,
/// and never written to a log, a status snapshot, or the MCP endpoint's URL:
/// the credential travels in a header only.
///
/// This type deliberately owns its `toString`: an accidental
/// `'$token'` prints `<redacted>`.
@immutable
final class ReleaseAccessToken {
  const ReleaseAccessToken._(this.value, this.issuedAt);

  /// Creates a fresh 256-bit token.
  ///
  /// [random] exists for deterministic tests; production callers must not pass
  /// one. [issuedAt] is for the audit trail.
  factory ReleaseAccessToken.generate({Random? random, DateTime? issuedAt}) {
    final source = random ?? Random.secure();
    final bytes = Uint8List(tokenBytes);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = source.nextInt(256);
    }
    final value = base64Url.encode(bytes).replaceAll('=', '');
    return ReleaseAccessToken._(value, (issuedAt ?? DateTime.now()).toUtc());
  }

  /// Entropy per token, in bytes (256 bits).
  static const int tokenBytes = 32;

  /// Length of [value]: base64url of [tokenBytes] without padding (43 chars).
  static const int tokenLength = 43;

  /// The secret. Never log it, never put it in a URL, never persist it in the
  /// APK.
  final String value;

  /// UTC instant this token was minted.
  final DateTime issuedAt;

  /// The header value to hand to a client: `Bearer <token>`.
  String get authorizationHeader => 'Bearer $value';

  /// Constant-time comparison against a candidate secret.
  ///
  /// Constant-time so a timing side channel cannot reveal the token byte by
  /// byte. Length is compared first; both tokens are fixed-length, so that
  /// comparison leaks nothing beyond "wrong token".
  bool matches(String candidate) {
    if (candidate.length != value.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < value.length; index++) {
      difference |= value.codeUnitAt(index) ^ candidate.codeUnitAt(index);
    }
    return difference == 0;
  }

  @override
  String toString() =>
      'ReleaseAccessToken(issuedAt: $issuedAt, value: <redacted>)';
}
