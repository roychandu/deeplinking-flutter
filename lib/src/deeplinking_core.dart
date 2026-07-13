import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'device_helper.dart';

class DeepLinking {
  static String? _baseUrl;
  static String? _appId;

  /// Configure the SDK with your DeepLinking base URL and App ID
  static void configure({required String baseUrl, required String appId}) {
    // Normalize baseUrl to remove trailing slash
    _baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    _appId = appId;
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

    // 1. Try to read from Clipboard for Direct Attribution
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text != null) {
        final text = clipboardData.text!.trim();

        // Parse Click ID: lt_cid_XXX
        if (text.contains('lt_cid_')) {
          final cidMatch = RegExp(r'lt_cid_([a-zA-Z0-9_-]+)').firstMatch(text);
          if (cidMatch != null) {
            clipboardCid = cidMatch.group(0);
          }

          // Parse Link ID: _lid_XXX
          final lidMatch = RegExp(r'_lid_([a-zA-Z0-9_-]+)').firstMatch(text);
          if (lidMatch != null) {
            parsedLinkId = lidMatch.group(1);
          }

          // Parse Allowed Screens: _scr_screen1,screen2
          final scrMatch = RegExp(r'_scr_([a-zA-Z0-9_,-]+)').firstMatch(text);
          if (scrMatch != null && scrMatch.group(1) != null) {
            allowedScreens = scrMatch
                .group(1)!
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }

          // Parse Referral Code: _ref_XXX
          final refMatch = RegExp(r'_ref_([a-zA-Z0-9_-]+)').firstMatch(text);
          if (refMatch != null) {
            parsedReferralCode = refMatch.group(1);
          }
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

    if (clipboardCid != null) {
      // Direct Attribution Mode
      requestBody['cid'] = clipboardCid;
      requestBody['linkId'] = parsedLinkId ?? linkId ?? '';
      if (allowedScreens != null)
        requestBody['allowedScreens'] = allowedScreens;
      if (parsedReferralCode != null)
        requestBody['referralCode'] = parsedReferralCode;
    } else {
      // Fingerprint / Manual Fallback Mode
      requestBody['linkId'] = linkId ?? '';
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
        return AttributionResult.fromJson(jsonResponse);
      } else {
        return null;
      }
    } catch (e) {
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
}
