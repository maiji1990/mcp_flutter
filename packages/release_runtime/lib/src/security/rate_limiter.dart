// packages/release_runtime/lib/src/security/rate_limiter.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

/// Sliding-window budget for tool calls.
///
/// [maxRequests] <= 0 disables the limiter. The window is process-global
/// because the current MCP SDK hands tool handlers no session id; with one
/// client (the recommended deployment) that is exactly the intended budget.
@immutable
final class ReleaseRateLimit {
  const ReleaseRateLimit({
    this.maxRequests = 0,
    this.window = const Duration(minutes: 1),
  });

  /// Calls allowed per [window]; 0 disables the limiter.
  final int maxRequests;

  /// Sliding window length.
  final Duration window;

  /// True when a budget is configured.
  bool get isEnabled => maxRequests > 0;
}

/// Counts calls in the current window and refuses the excess.
final class ReleaseRateLimiter {
  ReleaseRateLimiter(this.policy);

  final ReleaseRateLimit policy;
  final List<DateTime> _recent = <DateTime>[];

  /// Whether one more call fits in the window. Accepted calls are recorded.
  bool allow([DateTime? now]) {
    if (!policy.isEnabled) {
      return true;
    }
    final instant = now ?? DateTime.now();
    final cutoff = instant.subtract(policy.window);
    _recent.removeWhere((entry) => entry.isBefore(cutoff));
    if (_recent.length >= policy.maxRequests) {
      return false;
    }
    _recent.add(instant);
    return true;
  }

  /// Forgets the window (used by tests and a full reset).
  void reset() => _recent.clear();
}
