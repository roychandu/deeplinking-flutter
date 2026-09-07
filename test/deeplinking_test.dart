import 'package:flutter_test/flutter_test.dart';
import 'package:deeplinking/deeplinking.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttributionResult Model Tests', () {
    test('parses single screen and single permission for backward compatibility', () {
      final json = {
        'success': true,
        'method': 'direct',
        'data': {
          'clickId': 'cid_123',
          'referralCode': 'REF123',
          'screen': 'ProductDetail',
          'permission': 'read',
          'is_install': true,
          'params': {'productId': 'prod_999'},
        }
      };

      final result = AttributionResult.fromJson(json);

      expect(result.success, isTrue);
      expect(result.screen, equals('ProductDetail'));
      expect(result.screens, equals(['ProductDetail']));
      expect(result.allowedScreens, equals(['ProductDetail']));
      expect(result.permission, equals('read'));
      expect(result.permissions, equals(['read']));
      expect(result.hasPermission('read'), isTrue);
      expect(result.hasPermission('write'), isFalse);
      expect(result.allowsScreen('ProductDetail'), isTrue);
      expect(result.allowsScreen('Admin'), isFalse);
    });

    test('parses multiple screens as list and multiple permissions', () {
      final json = {
        'success': true,
        'method': 'direct',
        'data': {
          'clickId': 'cid_456',
          'screens': ['Home', 'Catalog', 'Promo'],
          'permissions': ['read', 'comment', 'vip'],
          'is_install': true,
        }
      };

      final result = AttributionResult.fromJson(json);

      expect(result.success, isTrue);
      expect(result.screen, equals('Home'));
      expect(result.screens, equals(['Home', 'Catalog', 'Promo']));
      expect(result.allowedScreens, equals(['Home', 'Catalog', 'Promo']));
      expect(result.permission, equals('read'));
      expect(result.permissions, equals(['read', 'comment', 'vip']));
      expect(result.hasPermission('comment'), isTrue);
      expect(result.hasPermission('admin'), isFalse);
      expect(result.allowsScreen('Catalog'), isTrue);
      expect(result.allowsScreen('Checkout'), isFalse);
    });

    test('parses comma-separated screens and permissions strings', () {
      final json = {
        'success': true,
        'data': {
          'screens': 'Dashboard, Analytics, Settings',
          'permissions': 'admin, manage, billing',
          'is_install': true,
        }
      };

      final result = AttributionResult.fromJson(json);

      expect(result.screens, equals(['Dashboard', 'Analytics', 'Settings']));
      expect(result.permissions, equals(['admin', 'manage', 'billing']));
      expect(result.hasPermission('admin'), isTrue);
      expect(result.hasPermission('billing'), isTrue);
      expect(result.allowsScreen('Settings'), isTrue);
    });

    test('parses granular per-screen permissions (screenPermissions)', () {
      final json = {
        'success': true,
        'data': {
          'screens': ['Store', 'AdminDashboard', 'Settings'],
          'permissions': ['read'],
          'screenPermissions': {
            'Store': ['view_item', 'buy'],
            'AdminDashboard': ['manage_users', 'export_reports'],
          },
          'is_install': true,
        }
      };

      final result = AttributionResult.fromJson(json);

      expect(result.hasScreenPermission('Store', 'buy'), isTrue);
      expect(result.hasScreenPermission('Store', 'manage_users'), isFalse);
      expect(result.hasScreenPermission('AdminDashboard', 'manage_users'), isTrue);
      expect(result.hasScreenPermission('Settings', 'read'), isTrue); // fallback to global permissions
    });

    test('parses screenPermissions when provided as JSON string', () {
      final json = {
        'success': true,
        'data': {
          'screens': ['Profile', 'Orders'],
          'screenPermissions': '{"Profile":["edit_bio"],"Orders":["cancel_order"]}',
        }
      };

      final result = AttributionResult.fromJson(json);

      expect(result.screenPermissions['Profile'], equals(['edit_bio']));
      expect(result.hasScreenPermission('Profile', 'edit_bio'), isTrue);
      expect(result.hasScreenPermission('Orders', 'cancel_order'), isTrue);
      expect(result.hasScreenPermission('Orders', 'edit_bio'), isFalse);
    });
  });

  group('DeepLinking Configuration Tests', () {
    test('throws ArgumentError on empty sdkKey', () {
      expect(
        () => DeepLinking.configure(
          baseUrl: 'https://deeplinking.in',
          appId: 'com.example.app',
          sdkKey: '   ',
        ),
        throwsArgumentError,
      );
    });

    test('configures successfully with valid parameters', () {
      expect(
        () => DeepLinking.configure(
          baseUrl: 'https://deeplinking.in/',
          appId: 'com.example.app',
          sdkKey: 'dlk_live_test123',
        ),
        returnsNormally,
      );
    });
  });
}
