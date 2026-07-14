import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'device_helper.dart';

class DeepLinking {
  static String? _baseUrl;
  static String? _appId;

  static const MethodChannel _sdkChannel = MethodChannel('deeplinking_sdk_channel');
  static bool _sdkChannelInitialized = false;
  static void Function(AttributionResult)? _attributionListener;

  /// Configure the SDK with your DeepLinking base URL and App ID
  static void configure({required String baseUrl, required String appId}) {
    // Normalize baseUrl to remove trailing slash
    _baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    _appId = appId;

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

  static Future<dynamic> _handleSdkMethodCall(MethodCall call) async {
    if (call.method == 'onClipboardData') {
      final map = call.arguments as Map?;
      final text = map?['text']?.toString();
      print('[SDK] onClipboardData received. text: "$text"');
      if (text != null && text.isNotEmpty) {
        print('[SDK] Calling trackInstall with clipboardText...');
        final result = await trackInstall(clipboardText: text);
        print('[SDK] trackInstall returned: success=${result?.success}, rawParams=${result?.rawParams}');
        if (result != null && result.success) {
          print('[SDK] Firing _attributionListener...');
          _attributionListener?.call(result);
          print('[SDK] _attributionListener fired. Listener was ${_attributionListener == null ? "NULL" : "set"}');
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
    if (_baseUrl == null || _appId == null) {
      throw StateError(
          'DeepLinking is not configured. Please call DeepLinking.configure() first.');
    }

    String? clipboardCid;
    String? parsedLinkId;
    List<String>? allowedScreens;
    String? parsedReferralCode;
    String? parsedShareId;
    String? parsedPermission;
    final Map<String, dynamic> localParams = {};

    // 1. Try to read from Clipboard for Direct Attribution
    try {
      final String? text = clipboardText?.trim() ?? 
          (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
      print('[SDKDebug] Resolved clipboard text: "$text"');
      if (text != null && text.isNotEmpty) {

        // ── A. Encoded token format: contains lt_cid_ and __lid_ ──
        if (text.contains('lt_cid_') && text.contains('__lid_')) {
          print('[SDKDebug] Clipboard matches encoded format');
          final cidMatch = RegExp(r'lt_cid_([a-zA-Z0-9_-]+?)(?:__|$)').firstMatch(text);
          if (cidMatch != null) {
            clipboardCid = cidMatch.group(1);
            print('[SDKDebug] Extracted CID: $clipboardCid');
          }

          final lidMatch = RegExp(r'__lid_([a-zA-Z0-9_-]+?)(?:__|$)').firstMatch(text);
          if (lidMatch != null) {
            parsedLinkId = lidMatch.group(1);
            print('[SDKDebug] Extracted LinkID: $parsedLinkId');
          }

          final refMatch = RegExp(r'__ref_([a-zA-Z0-9_-]+?)(?:__|$)').firstMatch(text);
          if (refMatch != null) {
            parsedReferralCode = refMatch.group(1);
            print('[SDKDebug] Extracted referralCode: $parsedReferralCode');
          }

          final shMatch = RegExp(r'__sh_([a-zA-Z0-9_-]+?)(?:__|$)').firstMatch(text);
          if (shMatch != null) {
            parsedShareId = shMatch.group(1);
            print('[SDKDebug] Extracted shareId: $parsedShareId');
          }

          final alsMatch = RegExp(r'__als_([a-zA-Z0-9_,-]+?)(?:__|$)').firstMatch(text);
          if (alsMatch != null && alsMatch.group(1) != null) {
            allowedScreens = alsMatch
                .group(1)!
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            print('[SDKDebug] Extracted allowedScreens: $allowedScreens');
          }

          final permMatch = RegExp(r'__perm_([a-zA-Z0-9_-]+?)(?:__|$)').firstMatch(text);
          if (permMatch != null) {
            parsedPermission = permMatch.group(1);
            print('[SDKDebug] Extracted permission: $parsedPermission');
          }
        }
        // ── B. Plain URL format: contains tracking path "/api/t/" ──
        else if (text.contains('/api/t/')) {
          print('[SDKDebug] Clipboard matches plain URL format (/api/t/)');
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

          // Parse query parameters
          // IMPORTANT: clipboard text may be multiline (e.g. share messages like
          // "Nike Air Force 1\n$109\n\nView on Store Room: https://...").
          // Uri.parse on the full text silently returns an empty URI.
          // We must extract just the URL first.
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
            }
            print('[SDKDebug] Extracted shareId: $parsedShareId');

            if (uri.queryParameters.containsKey('permission')) {
              parsedPermission = uri.queryParameters['permission'];
            }
            print('[SDKDebug] Extracted permission: $parsedPermission');

            if (uri.queryParameters.containsKey('allowedScreens')) {
              allowedScreens = uri.queryParameters['allowedScreens']!
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
            }
            print('[SDKDebug] Extracted allowedScreens: $allowedScreens');

            if (uri.queryParameters.containsKey('screen')) {
              localParams['screen'] = uri.queryParameters['screen'];
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
    }
    if (parsedPermission != null) {
      requestBody['permission'] = parsedPermission;
    }
    if (allowedScreens != null && allowedScreens.isNotEmpty) {
      requestBody['allowedScreens'] = allowedScreens.join(',');
    }

    // 4. Send network call to backend
    final url = Uri.parse('$_baseUrl/api/track-install');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final result = AttributionResult.fromJson(jsonResponse);
        if (localParams.isNotEmpty) {
          result.rawParams.addAll(localParams);
        }
        return result;
      } else {
        if (localParams.isNotEmpty) {
          return AttributionResult(
            success: true,
            isInstall: true,
            allowedScreens: allowedScreens ?? [],
            permission: parsedPermission,
            referralCode: parsedReferralCode,
            rawParams: localParams,
          );
        }
        return null;
      }
    } catch (e) {
      if (localParams.isNotEmpty) {
        return AttributionResult(
          success: true,
          isInstall: true,
          allowedScreens: allowedScreens ?? [],
          permission: parsedPermission,
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
  static Future<Map<String, dynamic>> redeemReferral({
    required String referralCode,
    required String newUserId,
    int? rewardDays,
  }) async {
    if (_baseUrl == null) {
      throw StateError(
          'DeepLinking is not configured. Please call DeepLinking.configure() first.');
    }

    final url = Uri.parse('$_baseUrl/api/redeem-referral');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'referralCode': referralCode,
        'newUserId': newUserId,
        if (rewardDays != null) 'rewardDays': rewardDays,
      }),
    );

    final jsonResponse = json.decode(response.body);
    if (response.statusCode == 200 && jsonResponse['success'] == true) {
      return jsonResponse;
    } else {
      throw Exception(
          jsonResponse['error'] ?? 'Failed to redeem referral code.');
    }
  }

  /// Tracks when a user shares a link (captures the product, screen, and user rankings).
  ///
  /// [linkId] - The tracking link ID being shared.
  /// [referralCode] - The sharing user's referral code.
  /// [screen] - The screen name from which the share was initiated.
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
    required String screen,
    String? referralUserId,
    String? referralFcmToken,
    String? fcmToken,
    String? platform,
    String? appVersion,
    String? source,
    String? eventId,
    Map<String, dynamic>? params,
  }) async {
    if (_baseUrl == null || _appId == null) {
      throw StateError(
          'DeepLinking is not configured. Please call DeepLinking.configure() first.');
    }

    final url = Uri.parse('$_baseUrl/api/track-share');
    final Map<String, dynamic> body = {
      'linkId': linkId,
      'referralCode': referralCode,
      'screen': screen,
      'appId': _appId,
      'eventId': eventId ?? 'share_${DateTime.now().millisecondsSinceEpoch}',
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
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );

    final jsonResponse = json.decode(response.body);
    if (response.statusCode == 200) {
      return jsonResponse;
    } else {
      throw Exception(jsonResponse['error'] ?? 'Failed to track share event.');
    }
  }

  /// Registers a share event with the tracking backend.
  static Future<Map<String, dynamic>> registerShare({
    required String linkId,
    required String screen,
    String? senderReferralCode,
    String? senderFcmToken,
    String? senderUserId,
    String? productId,
    String? permission,
    List<String>? allowedScreens,
  }) async {
    if (_baseUrl == null || _appId == null) {
      throw StateError('DeepLinking is not configured. Call DeepLinking.configure() first.');
    }

    final url = Uri.parse('$_baseUrl/api/shares/register');
    final Map<String, dynamic> body = {
      'linkId': linkId,
      'appId': _appId,
      'screen': screen,
      if (senderReferralCode != null) 'senderReferralCode': senderReferralCode,
      if (senderFcmToken != null) 'senderFcmToken': senderFcmToken,
      if (senderUserId != null) 'senderUserId': senderUserId,
      if (productId != null) 'productId': productId,
      if (permission != null) 'permission': permission,
      if (allowedScreens != null && allowedScreens.isNotEmpty)
        'allowedScreens': allowedScreens.join(','),
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );

    final jsonResponse = json.decode(response.body);
    if (response.statusCode == 200) {
      return jsonResponse;
    } else {
      throw Exception(jsonResponse['error'] ?? 'Failed to register share.');
    }
  }

  /// Registers the inviter's referral code and FCM token.
  static Future<Map<String, dynamic>> registerSender({
    required String referralCode,
    required String referralFcmToken,
    required String referralUserId,
    required String masterLink,
  }) async {
    if (_baseUrl == null || _appId == null) {
      throw StateError('DeepLinking is not configured. Call DeepLinking.configure() first.');
    }

    final url = Uri.parse('$_baseUrl/api/register-sender');
    final Map<String, dynamic> body = {
      'referralCode': referralCode,
      'referralFcmToken': referralFcmToken,
      'referralUserId': referralUserId,
      'masterLink': masterLink,
      'appId': _appId,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );

    final jsonResponse = json.decode(response.body);
    if (response.statusCode == 200) {
      return jsonResponse;
    } else {
      throw Exception(jsonResponse['error'] ?? 'Failed to register sender.');
    }
  }

  /// Fetches the referral history for a specific user.
  static Future<List<Map<String, dynamic>>> fetchReferralHistory(String userId) async {
    if (_baseUrl == null) {
      throw StateError('DeepLinking is not configured. Call DeepLinking.configure() first.');
    }

    final url = Uri.parse('$_baseUrl/api/referral-history?userId=$userId');
    final response = await http.get(
      url,
      headers: {'Content-Type': 'application/json'},
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
    if (_baseUrl == null) {
      throw StateError('DeepLinking is not configured. Call DeepLinking.configure() first.');
    }

    final url = Uri.parse('$_baseUrl/api/track-premium');
    await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'ref': referralCode,
        'app_id': appId,
      }),
    );
  }

  /// Syncs the user's FCM push notification token.
  static Future<void> syncFcmToken({
    required String linkId,
    required String fcmToken,
    String? referralCode,
    String? userId,
    String? shareId,
  }) async {
    if (_baseUrl == null || _appId == null) {
      throw StateError('DeepLinking is not configured. Call DeepLinking.configure() first.');
    }

    final url = Uri.parse('$_baseUrl/api/sync-fcm');
    final Map<String, dynamic> body = {
      'linkId': linkId,
      'appId': _appId,
      'fcmToken': fcmToken,
      if (referralCode != null) 'referralCode': referralCode,
      if (userId != null) 'userId': userId,
      if (shareId != null) 'shareId': shareId,
    };

    await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
  }

  /// Tracks when a deep link is opened directly by the app.
  static Future<void> trackDeepLinkOpen({
    required String linkId,
    required String screen,
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
    if (_baseUrl == null || _appId == null) {
      throw StateError('DeepLinking is not configured. Call DeepLinking.configure() first.');
    }

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
      'screen': screen,
      'targetId': targetId,
      if (referralCode != null) 'referralCode': referralCode,
      if (shareId != null) 'shareId': shareId,
      if (openedByFcmToken != null) 'openedByFcmToken': openedByFcmToken,
      if (openedByUserId != null) 'openedByUserId': openedByUserId,
      if (osVersion != null) 'osVersion': osVersion,
      if (appVersion != null) 'appVersion': appVersion,
      if (params != null) 'params': params,
    };

    await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
  }
}
