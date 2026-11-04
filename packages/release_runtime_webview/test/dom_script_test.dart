// packages/release_runtime_webview/test/dom_script_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release_webview/flutter_mcp_toolkit_release_webview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DOM snapshot script', () {
    test('embeds the origin allow-list, budgets, and nonce', () {
      final script = buildDomSnapshotScript(
        allowedOrigins: const <String>['https://app.example.com'],
        maxNodes: 25,
        maxDepth: 7,
        nonce: 'abc123',
      );

      expect(script, contains('https://app.example.com'));
      expect(script, contains('MAX_NODES = 25'));
      expect(script, contains('MAX_DEPTH = 7'));
      expect(script, contains('"abc123"'));
      expect(script, contains('location.origin'));
    });

    test('walks only interactive elements and marks secret fields', () {
      final script = buildDomSnapshotScript(
        allowedOrigins: const <String>['https://app.example.com'],
        maxNodes: 10,
        maxDepth: 3,
        nonce: 'abc',
      );

      expect(script, contains("button,a,input,textarea,select"));
      expect(script, contains('data-agent-sensitive'));
      expect(script, contains('type === \'password\''));
      expect(script, contains('[REDACTED]'));
      expect(script, contains('getBoundingClientRect'));
      // The whitespace normalizer must reach JavaScript as \s, not as s.
      expect(script, contains(r'/\s+/g'));
    });

    test('never returns cookies, storage, or raw HTML', () {
      final script = buildDomSnapshotScript(
        allowedOrigins: const <String>['https://app.example.com'],
        maxNodes: 10,
        maxDepth: 3,
        nonce: 'abc',
      );

      expect(script, isNot(contains('document.cookie')));
      expect(script, isNot(contains('localStorage')));
      expect(script, isNot(contains('outerHTML')));
      expect(script, isNot(contains('document.documentElement.innerHTML')));
    });
  });

  group('DOM action scripts', () {
    test('click carries the ref and nonce and re-checks the origin', () {
      final script = buildDomClickScript(
        allowedOrigins: const <String>['https://app.example.com'],
        ref: 'wabc_1',
        nonce: 'abc',
      );

      expect(script, contains('"wabc_1"'));
      expect(script, contains('"abc"'));
      expect(script, contains('origin_denied'));
      expect(script, contains('el.click()'));
      expect(script, contains('isConnected'));
      expect(script, contains('element_replaced'));
      expect(script, contains('role_changed'));
    });

    test('setText refuses password and sensitive controls', () {
      final script = buildDomSetTextScript(
        allowedOrigins: const <String>['https://app.example.com'],
        ref: 'wabc_1',
        nonce: 'abc',
        text: 'invoice 42',
      );

      expect(script, contains('target_sensitive'));
      expect(script, contains('data-agent-sensitive'));
      expect(script, contains('"invoice 42"'));
      expect(script, contains('dispatchEvent(new Event(\'input\''));
    });

    test('text is JSON encoded, not concatenated as code', () {
      final script = buildDomSetTextScript(
        allowedOrigins: const <String>['https://app.example.com'],
        ref: 'wabc_1',
        nonce: 'abc',
        text: "'); window.pwned = true; ('",
      );

      // The payload stays inside a JSON string literal: it never becomes code.
      expect(script, contains(r"'); window.pwned = true; ('"));
      final assignment = script.indexOf('var TEXT = ');
      expect(assignment, isNonNegative);
      expect(script.substring(assignment), startsWith('var TEXT = "'));
    });

    test('scroll validates a bounded amount', () {
      final script = buildDomScrollScript(
        allowedOrigins: const <String>['https://app.example.com'],
        ref: 'wabc_1',
        nonce: 'abc',
        direction: 'down',
        amount: 120,
      );

      expect(script, contains('"down"'));
      expect(script, contains('120.0'));
      expect(script, contains('scrollBy'));
    });
  });
}
