// packages/release_runtime/test/security/permissions_test.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.

import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:test/test.dart';

void main() {
  group('ReleasePermissionId', () {
    test('core permissions round-trip through their wire names', () {
      for (final permission in ReleasePermissionId.core) {
        expect(
          ReleasePermissionId.parse(permission.wireName),
          same(permission),
        );
        expect(permission.isAppPermission, isFalse);
        expect(permission.appName, isNull);
      }

      expect(ReleasePermissionId.uiRead.wireName, 'ui:read');
      expect(ReleasePermissionId.uiRead.isSensitive, isFalse);
      expect(ReleasePermissionId.uiInteract.isSensitive, isTrue);
      expect(ReleasePermissionId.uiCapture.isSensitive, isTrue);
    });

    test('app permissions carry a validated action name', () {
      final permission = ReleasePermissionId.app('pay.invoice');

      expect(permission.wireName, 'app:pay.invoice');
      expect(permission.isAppPermission, isTrue);
      expect(permission.appName, 'pay.invoice');
      expect(permission.isSensitive, isTrue);
      expect(ReleasePermissionId.parse('app:pay.invoice'), permission);
    });

    test('rejects malformed app names and unknown permission strings', () {
      final tooLong = List<String>.filled(65, 'a').join();
      for (final name in <String>['', 'Pay', '1pay', 'pay invoice', tooLong]) {
        expect(
          () => ReleasePermissionId.app(name),
          throwsA(
            isA<ReleaseMcpException>().having(
              (error) => error.code,
              'code',
              ReleaseMcpErrorCode.invalidPermissionId,
            ),
          ),
          reason: name,
        );
      }

      expect(ReleasePermissionId.tryParse('nonsense'), isNull);
      expect(ReleasePermissionId.tryParse('app:Pay'), isNull);
      expect(
        () => ReleasePermissionId.parse('custom:thing'),
        throwsA(
          isA<ReleaseMcpException>().having(
            (error) => error.code,
            'code',
            ReleaseMcpErrorCode.invalidPermissionId,
          ),
        ),
      );
    });
  });

  group('ReleasePermissionSet', () {
    test('read-only means no interactive, capture, or app permission', () {
      expect(ReleasePermissionSet.empty.isReadOnly, isTrue);
      expect(ReleasePermissionSet.readOnlyBase.isReadOnly, isTrue);
      expect(
        ReleasePermissionSet.readOnlyBase
            .union(
              ReleasePermissionSet(<ReleasePermissionId>[
                ReleasePermissionId.uiInteract,
              ]),
            )
            .isReadOnly,
        isFalse,
      );
      expect(
        ReleasePermissionSet(<ReleasePermissionId>[
          ReleasePermissionId.app('pay'),
        ]).isReadOnly,
        isFalse,
      );
    });

    test('union and difference are pure', () {
      final read = ReleasePermissionSet.readOnlyBase;
      final union = read.union(
        ReleasePermissionSet(<ReleasePermissionId>[
          ReleasePermissionId.uiCapture,
        ]),
      );

      expect(union.toWireList(), <String>['ui:capture', 'ui:read']);
      expect(read.toWireList(), <String>['ui:read']);
      expect(union.difference(read).toWireList(), <String>['ui:capture']);
    });

    test('equality ignores insertion order', () {
      final a = ReleasePermissionSet(<ReleasePermissionId>[
        ReleasePermissionId.uiRead,
        ReleasePermissionId.uiInteract,
      ]);
      final b = ReleasePermissionSet(<ReleasePermissionId>[
        ReleasePermissionId.uiInteract,
        ReleasePermissionId.uiRead,
      ]);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('start authorization defaults to no grants', () {
      final authorization = ReleaseStartAuthorization();

      expect(authorization.grantedPermissions, ReleasePermissionSet.empty);
      expect(authorization.toJson()['grantedPermissions'], isEmpty);
    });

    test('read-only authorization grants exactly ui:read', () {
      final authorization = ReleaseStartAuthorization.readOnly(reason: 'user');

      expect(authorization.grantedPermissions.toWireList(), <String>[
        'ui:read',
      ]);
      expect(authorization.reason, 'user');
    });
  });
}
