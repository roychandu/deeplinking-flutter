import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'device_helper.dart';

/// Throws [InvalidSdkKeyException] if [response] is a 401 or 403 authentication error
/// (missing key, invalid key, or app ID not registered).
/// Throws [SdkLimitExceededException] if [response] is a 429 rate-limit rejection.
void _throwIfAuthOrRateLimited(http.Response response) {
  if (response.statusCode == 401 || response.statusCode == 403) {
    Map<String, dynamic> body;
    try {
      body = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }
    throw InvalidSdkKeyException(
      body['error']?.toString() ?? 'Invalid or missing SDK key.',
      code: body['code']?.toString() ?? 'SDK_KEY_INVALID',
    );
  }

  if (response.statusCode == 429) {
    Map<String, dynamic> body;
    try {
      body = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }
    throw SdkLimitExceededException(
      body['error']?.toString() ?? 'Monthly SDK request limit reached.',
      used: body['used'] is int ? body['used'] as int : null,
      limit: body['limit'] is int ? body['limit'] as int : null,
    );
  }
}

class DeepLinking {
  static String? _baseUrl;
  static String? _appId;
  static String? _sdkKey;

  static const MethodChannel _sdkChannel = MethodChannel(
    'deeplinking_sdk_channel',
  );
  static bool _sdkChannelInitialized = false;
  static void Function(AttributionResult)? _attributionListener;

  /// Configure the SDK with your DeepLinking base URL, App ID, and SDK Key
  static void configure({
    required String baseUrl,
    required String appId,
    required String sdkKey,
  }) {
    if (sdkKey.trim().isEmpty) {
      throw ArgumentError('sdkKey cannot be empty.');
    }
    // Normalize baseUrl to remove trailing slash
    _baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    _appId = appId;
    _sdkKey = sdkKey.trim();

    if (!_sdkChannelInitialized) {
      _sdkChannelInitialized = true;
      _sdkChannel.setMethodCallHandler(_handleSdkMethodCall);
    }
  }

  /// Register a callback to be notified whenever clipboard install attribution succeeds.
  static void onInstallAttribution(void Function(AttributionResult) callback) {
    _attributionListener = callback;
  }

  static void Function(Map<String, String>)? _onDeepLinkOpenListener;

  /// Register a callback to be notified when a deep link intent is received.
  static void onDeepLinkOpen(void Function(Map<String, String>) callback) {
    _onDeepLinkOpenListener = callback;
  }

  static void Function(SharePermissionUpdate)? _onPermissionUpdatedListener;

  /// Register a callback to be notified when permissions for this device or shareId are updated in real-time.
  static void onPermissionUpdated(void Function(SharePermissionUpdate) callback) {
    _onPermissionUpdatedListener = callback;
  }

  static final StreamController<SharePermissionUpdate> _permissionUpdateController =
      StreamController<SharePermissionUpdate>.broadcast();

  /// Stream of real-time permission updates pushed from the backend via FCM.
  static Stream<SharePermissionUpdate> get permissionUpdates =>
      _permissionUpdateController.stream;

  /// ValueNotifier holding the latest permission update for easy integration with [ValueListenableBuilder].
  static final ValueNotifier<SharePermissionUpdate?> permissionUpdateNotifier =
      ValueNotifier<SharePermissionUpdate?>(null);

  /// Handles incoming push notification data (e.g. from FirebaseMessaging.onMessage or onBackgroundMessage).
  /// If the payload is a `permission_updated` event, it parses the permissions,
  /// updates [permissionUpdateNotifier], emits on [permissionUpdates], invokes any listener
  /// registered via [onPermissionUpdated], and returns the parsed [SharePermissionUpdate].
  static SharePermissionUpdate? handleNotificationData(Map<String, dynamic> data) {
    final type = data["type"]?.toString();
    final action = data["action"]?.toString();
    if (type == "permission_updated" || action == "update_permissions") {
      try {
        final update = SharePermissionUpdate.fromMap(data);
        permissionUpdateNotifier.value = update;
        _permissionUpdateController.add(update);
        if (_onPermissionUpdatedListener != null) {
          _onPermissionUpdatedListener!(update);
        }
        return update;
      } catch (e) {
        debugPrint("[DeepLinking] Error parsing permission update notification: $e");
      }
    }
    return null;
  }

  static Future<dynamic> _handleSdkMethodCall(MethodCall call) async {
    if (call.method == 'onClipboardData') {
      final map = call.arguments as Map?;
      final text = map?['text']?.toString();
      print('[SDK] onClipboardData received. text: "$text"');
      if (text != null && text.isNotEmpty) {
        print('[SDK] Calling trackInstall with clipboardText...');
        final result = await trackInstall(clipboardText: text);
        print(
          '[SDK] trackInstall returned: success=${result?.success}, rawParams=${result?.rawParams}',
        );
        if (result != null && result.success) {
          print('[SDK] Firing _attributionListener...');
          _attributionListener?.call(result);
          print(
            '[SDK] _attributionListener fired. Listener was ${_attributionListener == null ? "NULL" : "set"}',
          );
        } else {
          print('[SDK] result is null or success=false. Listener NOT fired.');
        }
      }
    } else if (call.method == 'openDeepLink') {
      print('[SDK] openDeepLink received from native: ${call.arguments}');
      final map = Map<String, dynamic>.from(call.arguments as Map);
      final params = map.map((key, value) => MapEntry(key, value.toString()));
      _onDeepLinkOpenListener?.call(params);
    }
    return null;
  }

  /// Automatically reads the clipboard to check for direct attribution click ID (CID).
  /// If found, attributes deterministically.
  /// If not found, gathers device metadata to attribute probabilistically (fingerprint fallback).
  ///
  /// [linkId] - Optional tracking link ID (recommended fallback if clipboard CID is not found).
  /// [installerFcmToken] - The FCM push notification token of the current user installing the app.
  /// [installerUserId] - The user ID of the current user.
  /// [appVersion] - The current app version.
  /// [customIp] - An optional override for the client IP (useful for local development testing).
  static Future<AttributionResult?> trackInstall({
    String? clipboardText,
    String? linkId,
    String? installerFcmToken,
    String? installerUserId,
    String? appVersion,
    String? customIp,
  }) async {
    if (_baseUrl == null || _appId == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Please call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    String? clipboardCid;
    String? parsedLinkId;
    String? parsedScreen;
    List<String>? parsedScreens;
    String? parsedReferralCode;
    String? parsedShareId;
    String? parsedPermission;
    List<String>? parsedPermissions;
    Map<String, dynamic>? parsedScreenPermissions;
    final Map<String, dynamic> localParams = {};

    // 1. Try to read from Clipboard for Direct Attribution
    try {
      final String? text =
          clipboardText?.trim() ??
          (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
      print('[SDKDebug] Resolved clipboard text: "$text"');
      if (text != null && text.isNotEmpty) {
        // ── A. Encoded token format: contains lt_cid_ and __lid_ ──
        if (text.contains('lt_cid_') && text.contains('__lid_')) {
          print('[SDKDebug] Clipboard matches encoded format');
          final cidMatch = RegExp(
            r'lt_cid_([a-zA-Z0-9_-]+?)(?:__|$)',
          ).firstMatch(text);
          if (cidMatch != null) {
            clipboardCid = cidMatch.group(1);
            print('[SDKDebug] Extracted CID: $clipboardCid');
          }

          final lidMatch = RegExp(
            r'__lid_([a-zA-Z0-9_-]+?)(?:__|$)',
          ).firstMatch(text);
          if (lidMatch != null) {
            parsedLinkId = lidMatch.group(1);
            print('[SDKDebug] Extracted LinkID: $parsedLinkId');
          }

          final refMatch = RegExp(
            r'__ref_([a-zA-Z0-9_-]+?)(?:__|$)',
          ).firstMatch(text);
          if (refMatch != null) {
            parsedReferralCode = refMatch.group(1);
            print('[SDKDebug] Extracted referralCode: $parsedReferralCode');
          }

          final shMatch = RegExp(
            r'__sh_([a-zA-Z0-9_-]+?)(?:__|$)',
          ).firstMatch(text);
          if (shMatch != null) {
            parsedShareId = shMatch.group(1);
            print('[SDKDebug] Extracted shareId: $parsedShareId');
            if (parsedShareId != null && parsedShareId.isNotEmpty) {
              localParams['shareId'] = parsedShareId;
              localParams['share_id'] = parsedShareId;
            }
          }

          // Check for multiple screens (__scrs_ or __als_)
          final scrsMatch = RegExp(
            r'__(?:scrs|als)_([a-zA-Z0-9_,-]+?)(?:__|$)',
          ).firstMatch(text);
          if (scrsMatch != null && scrsMatch.group(1) != null) {
            parsedScreens = scrsMatch
                .group(1)!
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            print('[SDKDebug] Extracted screens: $parsedScreens');
          }

          // Single screen (__scr_)
          final scrMatch = RegExp(
            r'__scr_([a-zA-Z0-9_-]+?)(?:__|$)',
          ).firstMatch(text);
          if (scrMatch != null) {
            parsedScreen = scrMatch.group(1);
            print('[SDKDebug] Extracted single screen: $parsedScreen');
          }

          // Multiple permissions (__perms_)
          final permsMatch = RegExp(
            r'__perms_([a-zA-Z0-9_,-]+?)(?:__|$)',
          ).firstMatch(text);
          if (permsMatch != null && permsMatch.group(1) != null) {
            parsedPermissions = permsMatch
                .group(1)!
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            print('[SDKDebug] Extracted permissions: $parsedPermissions');
          }

          // Single permission (__perm_)
          final permMatch = RegExp(
            r'__perm_([a-zA-Z0-9_-]+?)(?:__|$)',
          ).firstMatch(text);
          if (permMatch != null) {
            parsedPermission = permMatch.group(1);
            print('[SDKDebug] Extracted permission: $parsedPermission');
          }

          // Granular screen permissions (__sperms_)
          final spermsMatch = RegExp(
            r'__sperms_([^\n_]+?)(?:__|$)',
          ).firstMatch(text);
          if (spermsMatch != null && spermsMatch.group(1) != null) {
            try {
              final decoded = json.decode(Uri.decodeComponent(spermsMatch.group(1)!));
              if (decoded is Map) {
                parsedScreenPermissions = Map<String, dynamic>.from(decoded);
              }
            } catch (_) {}
          }
        }
        // ── B. Plain URL format: contains tracking path "/api/t/" or web URL ──
        else if (text.contains('/api/t/') || text.contains('http://') || text.contains('https://')) {
          print('[SDKDebug] Clipboard matches URL format');
          // Parse Link ID: find segment after /api/t/
          final trackingPathIndex = text.indexOf('/api/t/');
          if (trackingPathIndex != -1) {
            final startOfLinkId = trackingPathIndex + '/api/t/'.length;
            final endOfLinkId = text.indexOf(RegExp(r'[\?/\s]'), startOfLinkId);
            parsedLinkId = endOfLinkId != -1
                ? text.substring(startOfLinkId, endOfLinkId)
                : text.substring(startOfLinkId);
            print('[SDKDebug] Extracted LinkID: $parsedLinkId');
          }

          // Parse short link: find segment after /s/
          final shortPathIndex = text.indexOf('/s/');
          if (shortPathIndex != -1) {
            final startOfCode = shortPathIndex + '/s/'.length;
            final endOfCode = text.indexOf(RegExp(r'[\?/\s]'), startOfCode);
            final shortCode = endOfCode != -1
                ? text.substring(startOfCode, endOfCode)
                : text.substring(startOfCode);
            if (shortCode.isNotEmpty) {
              parsedShareId ??= shortCode;
              localParams['shortCode'] = shortCode;
              localParams['shareId'] = shortCode;
              print('[SDKDebug] Extracted shortCode: $shortCode');
            }
          }

          try {
            final urlMatch = RegExp(r'https?://\S+').firstMatch(text);
            final rawUrl = urlMatch?.group(0) ?? text;
            final uri = Uri.parse(rawUrl);
            if (uri.queryParameters.containsKey('ref')) {
              parsedReferralCode = uri.queryParameters['ref'];
            } else if (uri.queryParameters.containsKey('referralCode')) {
              parsedReferralCode = uri.queryParameters['referralCode'];
            }
            print('[SDKDebug] Extracted referralCode: $parsedReferralCode');

            if (uri.queryParameters.containsKey('shareId')) {
              parsedShareId = uri.queryParameters['shareId'];
            } else if (uri.queryParameters.containsKey('share_id')) {
              parsedShareId = uri.queryParameters['share_id'];
            } else if (uri.queryParameters.containsKey('s')) {
              parsedShareId = uri.queryParameters['s'];
            }
            print('[SDKDebug] Extracted shareId: $parsedShareId');
            if (parsedShareId != null && parsedShareId.isNotEmpty) {
              localParams['shareId'] = parsedShareId;
              localParams['share_id'] = parsedShareId;
              localParams['s'] = parsedShareId;
            }

            if (uri.queryParameters.containsKey('permission')) {
              parsedPermission = uri.queryParameters['permission'];
            }
            if (uri.queryParameters.containsKey('permissions')) {
              parsedPermissions = uri.queryParameters['permissions']!
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
            }
            print('[SDKDebug] Extracted permissions: $parsedPermissions, single: $parsedPermission');

            if (uri.queryParameters.containsKey('screens')) {
              parsedScreens = uri.queryParameters['screens']!
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
            } else if (uri.queryParameters.containsKey('allowedScreens')) {
              parsedScreens = uri.queryParameters['allowedScreens']!
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
            }
            print('[SDKDebug] Extracted screens: $parsedScreens');

            if (uri.queryParameters.containsKey('screen')) {
              parsedScreen = uri.queryParameters['screen'];
              localParams['screen'] = parsedScreen;
            }

            if (uri.queryParameters.containsKey('screenPermissions')) {
              try {
                final decoded = json.decode(uri.queryParameters['screenPermissions']!);
                if (decoded is Map) {
                  parsedScreenPermissions = Map<String, dynamic>.from(decoded);
                }
              } catch (_) {}
            }

            if (uri.queryParameters.containsKey('productId')) {
              localParams['productId'] = uri.queryParameters['productId'];
            } else if (uri.queryParameters.containsKey('product_id')) {
              localParams['productId'] = uri.queryParameters['product_id'];
            }
            print('[SDKDebug] Extracted localParams: $localParams');
          } catch (_) {}
        }
      }
    } catch (e) {
      // Clipboard read failed (e.g., restricted permissions or running on desktop without clipboard access)
    }

    // Combine screens list & primary screen
    final combinedScreens = parsedScreens ??
        (parsedScreen != null && parsedScreen.isNotEmpty ? [parsedScreen] : null);
    final primaryScreen = parsedScreen ??
        (combinedScreens != null && combinedScreens.isNotEmpty ? combinedScreens.first : null);

    // Combine permissions list & primary permission
    final combinedPermissions = parsedPermissions ??
        (parsedPermission != null && parsedPermission.isNotEmpty ? [parsedPermission] : null);
    final primaryPermission = parsedPermission ??
        (combinedPermissions != null && combinedPermissions.isNotEmpty ? combinedPermissions.first : null);

    // 2. Fetch device details for fallback fingerprint matching
    final deviceInfo = await DeviceHelper.getDeviceInfo();

    // 3. Construct API request body
    final Map<String, dynamic> requestBody = {
      'appId': _appId,
      'osName': deviceInfo['osName'],
      'osVersion': deviceInfo['osVersion'],
      'deviceModel': deviceInfo['deviceModel'],
      if (appVersion != null) 'appVersion': appVersion,
      if (installerFcmToken != null) 'fcmToken': installerFcmToken,
      if (installerFcmToken != null) 'openedByFcmToken': installerFcmToken,
      if (installerUserId != null) 'openedByUserId': installerUserId,
      if (customIp != null) 'ip': customIp,
    };

    // Use parsed values from clipboard if available, fallback to function arguments
    final finalLinkId = parsedLinkId ?? linkId ?? '';
    requestBody['linkId'] = finalLinkId;

    if (clipboardCid != null) {
      requestBody['cid'] = clipboardCid;
    }
    if (parsedReferralCode != null) {
      requestBody['referralCode'] = parsedReferralCode;
    }
    if (parsedShareId != null) {
      requestBody['shareId'] = parsedShareId;
      requestBody['share_id'] = parsedShareId;
      requestBody['shared_id'] = parsedShareId;
      requestBody['s'] = parsedShareId;
    }
    if (primaryScreen != null) {
      requestBody['screen'] = primaryScreen;
    }
    if (combinedScreens != null && combinedScreens.isNotEmpty) {
      requestBody['screens'] = combinedScreens;
      requestBody['allowedScreens'] = combinedScreens.join(',');
    }
    if (primaryPermission != null) {
      requestBody['permission'] = primaryPermission;
    }
    if (combinedPermissions != null && combinedPermissions.isNotEmpty) {
      requestBody['permissions'] = combinedPermissions;
    }
    if (parsedScreenPermissions != null && parsedScreenPermissions.isNotEmpty) {
      requestBody['screenPermissions'] = parsedScreenPermissions;
    }

    // 4. Send network call to backend
    final url = Uri.parse('$_baseUrl/api/track-install');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
        body: json.encode(requestBody),
      );

      _throwIfAuthOrRateLimited(response);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final result = AttributionResult.fromJson(jsonResponse);
        if (localParams.isNotEmpty) {
          result.rawParams.addAll(localParams);
        }
        return result;
      } else {
        if (localParams.isNotEmpty || combinedScreens != null || parsedReferralCode != null) {
          return AttributionResult(
            success: true,
            isInstall: true,
            shareId: parsedShareId,
            screen: primaryScreen,
            screens: combinedScreens ?? [],
            allowedScreens: combinedScreens ?? [],
            permission: primaryPermission,
            permissions: combinedPermissions ?? [],
            screenPermissions: parsedScreenPermissions ?? {},
            referralCode: parsedReferralCode,
            rawParams: localParams,
          );
        }
        return null;
      }
    } on SdkLimitExceededException {
      // The backend explicitly rejected this request because the plan's
      // monthly SDK quota is exhausted.
      rethrow;
    } on InvalidSdkKeyException {
      // The backend explicitly rejected this request because the SDK key
      // is missing, invalid, or app ID is not registered under the key owner's workspace.
      rethrow;
    } catch (e) {
      if (localParams.isNotEmpty || combinedScreens != null || parsedReferralCode != null) {
        return AttributionResult(
          success: true,
          isInstall: true,
          screen: primaryScreen,
          screens: combinedScreens ?? [],
          allowedScreens: combinedScreens ?? [],
          permission: primaryPermission,
          permissions: combinedPermissions ?? [],
          screenPermissions: parsedScreenPermissions ?? {},
          referralCode: parsedReferralCode,
          rawParams: localParams,
        );
      }
      return null;
    }
  }

  /// Redeems a referral code, crediting both the referrer and the current installer.
  /// Returns the API response map on success, or throws an exception on failure.
  ///
  /// [referralCode] - The referral code to redeem.
  /// [newUserId] - The user ID of the newly installed client.
  /// [rewardDays] - Optional customization of the number of premium reward days to credit.
  /// [linkId] - Optional tracking link ID, so this call is attributed to that
  /// link's usage total (recommended: pass your app's master link ID).
  static Future<Map<String, dynamic>> redeemReferral({
    required String referralCode,
    required String newUserId,
    int? rewardDays,
    String? linkId,
  }) async {
    if (_baseUrl == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Please call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final url = Uri.parse('$_baseUrl/api/redeem-referral');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
      body: json.encode({
        'referralCode': referralCode,
        'newUserId': newUserId,
        if (rewardDays != null) 'rewardDays': rewardDays,
        if (linkId != null) 'linkId': linkId,
      }),
    );

    _throwIfAuthOrRateLimited(response);

    final jsonResponse = json.decode(response.body);
    if (response.statusCode == 200 && jsonResponse['success'] == true) {
      return jsonResponse;
    } else {
      throw Exception(
        jsonResponse['error'] ?? 'Failed to redeem referral code.',
      );
    }
  }

  /// Tracks when a user shares a link (captures the product, screens, permissions, and rankings).
  ///
  /// [linkId] - The tracking link ID being shared.
  /// [referralCode] - The sharing user's referral code.
  /// [screen] - The primary screen name from which the share was initiated.
  /// [screens] - Multiple target screens allowed/intended for the shared link.
  /// [allowedScreens] - Synonym/alias for [screens].
  /// [permission] - Single permission level (e.g. "read", "vip").
  /// [permissions] - Multiple permissions granted for this share.
  /// [screenPermissions] - Granular per-screen permissions map.
  /// [referralUserId] - The user ID of the referrer.
  /// [referralFcmToken] - The FCM token of the referrer.
  /// [fcmToken] - Optional FCM token of the current user.
  /// [platform] - Device platform (e.g. 'iOS', 'Android').
  /// [appVersion] - Client app version.
  /// [source] - Share channel/source (e.g., 'WhatsApp', 'Facebook').
  /// [eventId] - Optional deduplication event ID. Will auto-generate if null.
  /// [params] - Optional custom key-value params for the share.
  static Future<Map<String, dynamic>> trackShare({
    required String linkId,
    required String referralCode,
    String? screen,
    List<String>? screens,
    List<String>? allowedScreens,
    String? permission,
    List<String>? permissions,
    Map<String, dynamic>? screenPermissions,
    String? referralUserId,
    String? referralFcmToken,
    String? fcmToken,
    String? platform,
    String? appVersion,
    String? source,
    String? eventId,
    Map<String, dynamic>? params,
  }) async {
    if (_baseUrl == null || _appId == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Please call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final combinedScreens = screens ??
        allowedScreens ??
        (screen != null && screen.isNotEmpty ? [screen] : null);
    final primaryScreen = screen ??
        (combinedScreens != null && combinedScreens.isNotEmpty
            ? combinedScreens.first
            : 'Home');

    final combinedPermissions = permissions ??
        (permission != null && permission.isNotEmpty ? [permission] : null);
    final primaryPermission = permission ??
        (combinedPermissions != null && combinedPermissions.isNotEmpty
            ? combinedPermissions.first
            : null);

    final url = Uri.parse('$_baseUrl/api/track-share');
    final Map<String, dynamic> body = {
      'linkId': linkId,
      'referralCode': referralCode,
      'screen': primaryScreen,
      'appId': _appId,
      'eventId': eventId ?? 'share_${DateTime.now().millisecondsSinceEpoch}',
      if (combinedScreens != null && combinedScreens.isNotEmpty)
        'screens': combinedScreens,
      if (combinedScreens != null && combinedScreens.isNotEmpty)
        'allowedScreens': combinedScreens.join(','),
      if (primaryPermission != null) 'permission': primaryPermission,
      if (combinedPermissions != null && combinedPermissions.isNotEmpty)
        'permissions': combinedPermissions,
      if (screenPermissions != null && screenPermissions.isNotEmpty)
        'screenPermissions': screenPermissions,
      if (referralUserId != null) 'referralUserId': referralUserId,
      if (referralFcmToken != null) 'referralFcmToken': referralFcmToken,
      if (fcmToken != null) 'fcmToken': fcmToken,
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
      if (source != null) 'source': source,
      if (params != null) 'params': params,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
      body: json.encode(body),
    );

    _throwIfAuthOrRateLimited(response);

    final jsonResponse = json.decode(response.body);
    if (response.statusCode == 200) {
      return jsonResponse;
    } else {
      throw Exception(jsonResponse['error'] ?? 'Failed to track share event.');
    }
  }

  /// Registers a share event with the tracking backend.
  ///
  /// Supports single [screen] or multiple [screens] / [allowedScreens],
  /// single [permission] or multiple [permissions], and granular [screenPermissions].
  static Future<Map<String, dynamic>> registerShare({
    required String linkId,
    String? shareId,
    String? screen,
    List<String>? screens,
    List<String>? allowedScreens,
    String? permission,
    List<String>? permissions,
    Map<String, dynamic>? screenPermissions,
    String? senderReferralCode,
    String? senderFcmToken,
    String? senderUserId,
    String? productId,
  }) async {
    if (_baseUrl == null || _appId == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final combinedScreens = screens ??
        allowedScreens ??
        (screen != null && screen.isNotEmpty ? [screen] : null);
    final primaryScreen = screen ??
        (combinedScreens != null && combinedScreens.isNotEmpty
            ? combinedScreens.first
            : null);

    final combinedPermissions = permissions ??
        (permission != null && permission.isNotEmpty ? [permission] : null);
    final primaryPermission = permission ??
        (combinedPermissions != null && combinedPermissions.isNotEmpty
            ? combinedPermissions.first
            : null);

    final url = Uri.parse('$_baseUrl/api/shares/register');
    final Map<String, dynamic> body = {
      'linkId': linkId,
      'appId': _appId,
      if (shareId != null) ...{
        'shareId': shareId,
        'share_id': shareId,
        'shared_id': shareId,
        's': shareId,
      },
      if (primaryScreen != null) 'screen': primaryScreen,
      if (combinedScreens != null && combinedScreens.isNotEmpty)
        'screens': combinedScreens,
      if (combinedScreens != null && combinedScreens.isNotEmpty)
        'allowedScreens': combinedScreens.join(','),
      if (primaryPermission != null) 'permission': primaryPermission,
      if (combinedPermissions != null && combinedPermissions.isNotEmpty)
        'permissions': combinedPermissions,
      if (screenPermissions != null && screenPermissions.isNotEmpty)
        'screenPermissions': screenPermissions,
      if (senderReferralCode != null) 'senderReferralCode': senderReferralCode,
      if (senderFcmToken != null) 'senderFcmToken': senderFcmToken,
      if (senderUserId != null) 'senderUserId': senderUserId,
      if (productId != null) 'productId': productId,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
      body: json.encode(body),
    );

    _throwIfAuthOrRateLimited(response);

    final jsonResponse = json.decode(response.body);
    if (response.statusCode == 200) {
      return jsonResponse;
    } else {
      throw Exception(jsonResponse['error'] ?? 'Failed to register share.');
    }
  }



  /// Updates an existing share record in the database with updated permissions,
  /// screens, and target parameters in real-time.
  ///
  /// Calls  on the tracking backend.
  static Future<Map<String, dynamic>> updateShare({
    required String linkId,
    required String shareId,
    String? screen,
    List<String>? screens,
    List<String>? allowedScreens,
    String? permission,
    List<String>? permissions,
    Map<String, dynamic>? screenPermissions,
    String? productId,
    bool? notifySender,
    String? notificationTitle,
    String? notificationBody,
    bool? silent,
  }) async {
    if (_baseUrl == null || _appId == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final combinedScreens = screens ??
        allowedScreens ??
        (screen != null && screen.isNotEmpty ? [screen] : null);
    final primaryScreen = screen ??
        (combinedScreens != null && combinedScreens.isNotEmpty
            ? combinedScreens.first
            : null);

    final combinedPermissions = permissions ??
        (permission != null && permission.isNotEmpty ? [permission] : null);
    final primaryPermission = permission ??
        (combinedPermissions != null && combinedPermissions.isNotEmpty
            ? combinedPermissions.first
            : null);

    final url = Uri.parse('$_baseUrl/api/shares/update');
    final Map<String, dynamic> body = {
      'linkId': linkId,
      'shareId': shareId,
      'share_id': shareId,
      'shared_id': shareId,
      's': shareId,
      'appId': _appId,
      if (primaryScreen != null) 'screen': primaryScreen,
      if (combinedScreens != null && combinedScreens.isNotEmpty)
        'screens': combinedScreens,
      if (combinedScreens != null && combinedScreens.isNotEmpty)
        'allowedScreens': combinedScreens.join(','),
      if (primaryPermission != null) 'permission': primaryPermission,
      if (combinedPermissions != null && combinedPermissions.isNotEmpty)
        'permissions': combinedPermissions,
      if (screenPermissions != null && screenPermissions.isNotEmpty)
        'screenPermissions': screenPermissions,
      if (productId != null) 'productId': productId,
      if (notifySender != null) 'notifySender': notifySender,
      if (notificationTitle != null) 'notificationTitle': notificationTitle,
      if (notificationBody != null) 'notificationBody': notificationBody,
      if (silent != null) 'silent': silent,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
      body: json.encode(body),
    );

    _throwIfAuthOrRateLimited(response);

    final jsonResponse = json.decode(response.body);
    if (response.statusCode == 200) {
      return jsonResponse;
    } else {
      throw Exception(jsonResponse['error'] ?? 'Failed to update share.');
    }
  }

  /// Retrieves the latest live permissions, screens, and parameters for an existing share from the backend database.
  static Future<Map<String, dynamic>?> getShareDetails({
    required String linkId,
    String? shareId,
    String? userId,
  }) async {
    if (_baseUrl == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final queryParams = <String, String>{
      'linkId': linkId,
      if (shareId != null && shareId.isNotEmpty) ...{
        'shareId': shareId,
        'share_id': shareId,
        'shared_id': shareId,
        's': shareId,
      },
      if (userId != null && userId.isNotEmpty) 'userId': userId,
    };

    final url = Uri.parse('$_baseUrl/api/shares/details')
        .replace(queryParameters: queryParams);
    final response = await http.get(
      url,
      headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
    );

    _throwIfAuthOrRateLimited(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    }
    return null;
  }

  /// Generates a branded short URL for a tracking link or share.
  /// Calls  on the backend.
  static Future<Map<String, dynamic>> shortenLink({
    required String linkId,
    String? shareId,
    String? customCode,
    String? customDomain,
  }) async {
    if (_baseUrl == null || _appId == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final url = Uri.parse('/api/links/shorten');
    final Map<String, dynamic> body = {
      'linkId': linkId,
      'appId': _appId,
      if (shareId != null) ...{
        'shareId': shareId,
        'share_id': shareId,
        'shared_id': shareId,
        's': shareId,
      },
      if (customCode != null) 'customCode': customCode,
      if (customDomain != null) 'customDomain': customDomain,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
      body: json.encode(body),
    );

    _throwIfAuthOrRateLimited(response);

    final jsonResponse = json.decode(response.body);
    if (response.statusCode == 200) {
      return jsonResponse;
    } else {
      throw Exception(jsonResponse['error'] ?? 'Failed to shorten link.');
    }
  }

  /// Registers the inviter's referral code and FCM token.
  ///
  /// [linkId] - Optional tracking link ID, so this call is attributed to that
  /// link's usage total (recommended: pass your app's master link ID).
  static Future<Map<String, dynamic>> registerSender({
    required String referralCode,
    required String referralFcmToken,
    required String referralUserId,
    required String masterLink,
    String? linkId,
  }) async {
    if (_baseUrl == null || _appId == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final url = Uri.parse('$_baseUrl/api/register-sender');
    final Map<String, dynamic> body = {
      'referralCode': referralCode,
      'referralFcmToken': referralFcmToken,
      'referralUserId': referralUserId,
      'masterLink': masterLink,
      'appId': _appId,
      if (linkId != null) 'linkId': linkId,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
      body: json.encode(body),
    );

    _throwIfAuthOrRateLimited(response);

    final jsonResponse = json.decode(response.body);
    if (response.statusCode == 200) {
      return jsonResponse;
    } else {
      throw Exception(jsonResponse['error'] ?? 'Failed to register sender.');
    }
  }

  /// Fetches the referral history for a specific user.
  static Future<List<Map<String, dynamic>>> fetchReferralHistory(
    String userId,
  ) async {
    if (_baseUrl == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final url = Uri.parse('$_baseUrl/api/referral-history?userId=$userId');
    final response = await http.get(
      url,
      headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
    );

    final jsonResponse = json.decode(response.body);
    if (response.statusCode == 200 && jsonResponse['success'] == true) {
      if (jsonResponse['history'] is List) {
        return List<Map<String, dynamic>>.from(jsonResponse['history']);
      }
    }
    return [];
  }

  /// Tracks a premium subscription/upgrade action.
  static Future<void> trackPremium({
    required String referralCode,
    required String appId,
  }) async {
    if (_baseUrl == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final url = Uri.parse('$_baseUrl/api/track-premium');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
      body: json.encode({'ref': referralCode, 'app_id': appId}),
    );
    _throwIfAuthOrRateLimited(response);
  }

  /// Syncs the user's FCM push notification token.
  static Future<void> syncFcmToken({
    required String linkId,
    required String fcmToken,
    String? referralCode,
    String? userId,
    String? shareId,
    String? clickId,
  }) async {
    if (_baseUrl == null || _appId == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final url = Uri.parse('$_baseUrl/api/sync-fcm');
    final Map<String, dynamic> body = {
      'linkId': linkId,
      'appId': _appId,
      'fcmToken': fcmToken,
      if (referralCode != null) 'referralCode': referralCode,
      if (userId != null) 'userId': userId,
      if (shareId != null) ...{
        'shareId': shareId,
        'share_id': shareId,
        'shared_id': shareId,
        's': shareId,
      },
      if (clickId != null) 'clickId': clickId,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
      body: json.encode(body),
    );
    _throwIfAuthOrRateLimited(response);
  }

  /// Tracks when a deep link is opened directly by the app.
  static Future<Map<String, dynamic>> trackDeepLinkOpen({
    required String linkId,
    String? screen,
    List<String>? screens,
    List<String>? allowedScreens,
    String? permission,
    List<String>? permissions,
    Map<String, dynamic>? screenPermissions,
    required String targetId,
    required String appState,
    String? referralCode,
    String? shareId,
    String? openedByFcmToken,
    String? openedByUserId,
    String? platform,
    String? appVersion,
    String? osVersion,
    Map<String, dynamic>? params,
  }) async {
    if (_baseUrl == null || _appId == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final combinedScreens = screens ??
        allowedScreens ??
        (screen != null && screen.isNotEmpty ? [screen] : null);
    final primaryScreen = screen ??
        (combinedScreens != null && combinedScreens.isNotEmpty
            ? combinedScreens.first
            : 'Home');

    final combinedPermissions = permissions ??
        (permission != null && permission.isNotEmpty ? [permission] : null);
    final primaryPermission = permission ??
        (combinedPermissions != null && combinedPermissions.isNotEmpty
            ? combinedPermissions.first
            : null);

    final url = Uri.parse('$_baseUrl/api/track-deep-link-open');
    final Map<String, dynamic> body = {
      'eventId': 'dl_open_${DateTime.now().millisecondsSinceEpoch}',
      'linkId': linkId,
      'appId': _appId,
      'app_id': _appId,
      'eventType': 'direct_open',
      'appState': appState,
      'source': 'app_link',
      'platform': platform ?? 'android',
      'screen': primaryScreen,
      if (combinedScreens != null && combinedScreens.isNotEmpty)
        'screens': combinedScreens,
      if (combinedScreens != null && combinedScreens.isNotEmpty)
        'allowedScreens': combinedScreens.join(','),
      if (primaryPermission != null) 'permission': primaryPermission,
      if (combinedPermissions != null && combinedPermissions.isNotEmpty)
        'permissions': combinedPermissions,
      if (screenPermissions != null && screenPermissions.isNotEmpty)
        'screenPermissions': screenPermissions,
      'targetId': targetId,
      if (referralCode != null) 'referralCode': referralCode,
      if (shareId != null) ...{
        'shareId': shareId,
        'share_id': shareId,
        'shared_id': shareId,
        's': shareId,
      },
      if (openedByFcmToken != null) 'openedByFcmToken': openedByFcmToken,
      if (openedByUserId != null) 'openedByUserId': openedByUserId,
      if (osVersion != null) 'osVersion': osVersion,
      if (appVersion != null) 'appVersion': appVersion,
      if (params != null) 'params': params,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'X-SDK-Key': _sdkKey!},
      body: json.encode(body),
    );
    _throwIfAuthOrRateLimited(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  /// Fetches the active plan associated with the configured SDK Key.
  /// Resolves the plan tier (e.g., 'free', 'base', 'pro', 'enterprise').
  static Future<String> getActivePlan() async {
    if (_baseUrl == null || _sdkKey == null) {
      throw StateError(
        'DeepLinking is not configured. Please call DeepLinking.configure() first with a valid SDK Key.',
      );
    }

    final url = Uri.parse(
      '$_baseUrl/api/sdk/plan?key=${Uri.encodeComponent(_sdkKey!)}',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        return jsonResponse['plan'] ?? 'base';
      }
    } catch (_) {
      // Fallback on network errors
    }
    return 'base';
  }
}
