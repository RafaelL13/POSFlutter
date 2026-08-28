import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/role_policy.dart';
import 'package:pos_app/core/context/local_app_context.dart';

void main() {
  group('AuthorizationService', () {
    test('builds effective offline permissions from local context', () async {
      final authorization = await AuthorizationService.fromContextLoader(
        () async => _context(role: 'Manager'),
      ).load();

      expect(authorization.hasValidContext, isTrue);
      expect(
        authorization.permissionFor(Capability.productWrite),
        PermissionLevel.full,
      );
      expect(authorization.can(Capability.viewProfit), isTrue);
      expect(authorization.can(Capability.usersWrite), isFalse);
    });

    test('unknown role fails closed', () async {
      final authorization = await AuthorizationService.fromContextLoader(
        () async => _context(role: 'Root'),
      ).load();

      expect(authorization.hasValidContext, isFalse);
      expect(authorization.grantedCapabilities, isEmpty);
      expect(
        authorization.permissionFor(Capability.saleCreate),
        PermissionLevel.none,
      );
    });

    test('unknown device mode fails closed', () async {
      final authorization = await AuthorizationService.fromContextLoader(
        () async => _context(deviceMode: 'Kiosk'),
      ).load();

      expect(authorization.hasValidContext, isFalse);
      expect(authorization.grantedCapabilities, isEmpty);
    });

    test('missing or inactive local context fails closed', () async {
      final authorization = await AuthorizationService.fromContextLoader(
        () async => throw StateError('No active user or device.'),
      ).load();

      expect(authorization.hasValidContext, isFalse);
      expect(authorization.grantedCapabilities, isEmpty);
    });

    test('AdminReadOnly reduces administrator permissions', () async {
      final authorization = await AuthorizationService.fromContextLoader(
        () async => _context(deviceMode: 'AdminReadOnly'),
      ).load();

      expect(authorization.can(Capability.productRead), isTrue);
      expect(authorization.can(Capability.productWrite), isFalse);
      expect(authorization.can(Capability.syncPull), isTrue);
      expect(authorization.can(Capability.syncPush), isFalse);
    });
  });

  group('EffectiveCapabilities.require', () {
    test('allows directly granted capability', () {
      final authorization = EffectiveCapabilities.fromContext(
        _context(role: 'Seller'),
      );

      expect(
        () => authorization.require(Capability.saleCreate),
        returnsNormally,
      );
    });

    test('throws typed exception for denied capability', () {
      final authorization = EffectiveCapabilities.fromContext(
        _context(role: 'Seller'),
      );

      expect(
        () => authorization.require(Capability.purchaseCreate),
        throwsA(isA<AuthorizationDeniedException>()),
      );
    });

    test('does not bypass additional authorization', () {
      final authorization = EffectiveCapabilities.fromContext(
        _context(role: 'Seller'),
      );

      expect(
        authorization.requiresAdditionalAuthorization(Capability.saleCancel),
        isTrue,
      );
      expect(
        () => authorization.require(Capability.saleCancel),
        throwsA(isA<AdditionalAuthorizationRequiredException>()),
      );
    });
  });
}

LocalAppContext _context({
  String role = 'Administrator',
  String deviceMode = 'PointOfSale',
}) {
  return LocalAppContext(
    businessId: 1,
    businessGlobalId: 'business-1',
    branchId: 2,
    branchGlobalId: 'branch-1',
    deviceId: 3,
    deviceGlobalId: 'device-1',
    deviceMode: deviceMode,
    userId: 4,
    userGlobalId: 'user-1',
    role: role,
  );
}
