import 'dart:convert';

/// Thrown when the backend rejects a call because the plan's monthly SDK
/// request limit has been reached (HTTP 429, code RATE_LIMIT_EXCEEDED).
class SdkLimitExceededException implements Exception {
  final String message;
  final int? used;
  final int? limit;

  SdkLimitExceededException(this.message, {this.used, this.limit});

  @override
  String toString() => 'SdkLimitExceededException: $message';
}

/// Thrown when the backend rejects an SDK call because the provided SDK key
/// is missing, invalid, format error, or app ID is not registered (HTTP 401 / 403).
class InvalidSdkKeyException implements Exception {
  final String message;
  final String? code;

  InvalidSdkKeyException(this.message, {this.code});

  @override
  String toString() =>
      'InvalidSdkKeyException: $message (code: ${code ?? 'SDK_KEY_INVALID'})';
}

/// Result model representing the outcome of install or deep link attribution.
class AttributionResult {
  final bool success;
  final String? method;
  final String? clickId;
  final String? referralCode;
  final String? referralUserId;
  final String? referralFcmToken;
  final String? customReferrer;
  final String? shareId;
  final bool isInstall;
  final int? attributionScore;

  /// Primary target screen name (e.g. "ProductDetail", "Catalog").
  final String? screen;

  /// List of target screens associated with this deep link or install.
  final List<String> screens;

  /// Synonym/alias for [screens] for full backward compatibility.
  final List<String> allowedScreens;

  /// Single primary permission (e.g. "read", "vip_access").
  final String? permission;

  /// List of all granted permissions (e.g. ["read", "write", "vip_access"]).
  final List<String> permissions;

  /// Granular per-screen permission mappings (e.g. {"ProductDetail": ["view", "buy"], "Admin": ["admin"]}).
  final Map<String, dynamic> screenPermissions;

  final Map<String, dynamic> rawParams;

  AttributionResult({
    required this.success,
    this.method,
    this.clickId,
    this.referralCode,
    this.referralUserId,
    this.referralFcmToken,
    this.customReferrer,
    this.shareId,
    required this.isInstall,
    this.attributionScore,
    this.screen,
    List<String>? screens,
    List<String>? allowedScreens,
    this.permission,
    List<String>? permissions,
    Map<String, dynamic>? screenPermissions,
    required this.rawParams,
  })  : screens = screens ??
            allowedScreens ??
            (screen != null && screen.isNotEmpty ? [screen] : []),
        allowedScreens = allowedScreens ??
            screens ??
            (screen != null && screen.isNotEmpty ? [screen] : []),
        permissions = permissions ??
            (permission != null && permission.isNotEmpty ? [permission] : []),
        screenPermissions = screenPermissions ?? {};

  /// Checks if a global permission or any screen permission grants [permissionName].
  bool hasPermission(String permissionName) {
    if (permissions.contains(permissionName)) return true;
    for (final entry in screenPermissions.values) {
      if (entry is List && entry.contains(permissionName)) return true;
      if (entry is String && entry == permissionName) return true;
    }
    return false;
  }

  /// Checks if a specific screen allows [permissionName].
  bool hasScreenPermission(String screenName, String permissionName) {
    if (permissions.contains(permissionName)) return true;
    final screenPerm = screenPermissions[screenName];
    if (screenPerm is List) {
      return screenPerm.contains(permissionName);
    } else if (screenPerm is String) {
      return screenPerm == permissionName;
    }
    return false;
  }

  /// Checks if [screenName] is in the list of allowed/target screens.
  bool allowsScreen(String screenName) {
    if (screens.isEmpty && allowedScreens.isEmpty) return true;
    return screens.contains(screenName) || allowedScreens.contains(screenName);
  }

  factory AttributionResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};

    // 1. Parse screens / allowedScreens
    List<String> parsedScreens = [];
    if (data['screens'] != null) {
      if (data['screens'] is List) {
        parsedScreens = (data['screens'] as List)
            .map((e) => e.toString().trim())
            .where((String s) => s.isNotEmpty)
            .toList();
      } else if (data['screens'] is String) {
        parsedScreens = data['screens']
            .toString()
            .split(',')
            .map((s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toList();
      }
    } else if (data['allowedScreens'] != null) {
      if (data['allowedScreens'] is List) {
        parsedScreens = (data['allowedScreens'] as List)
            .map((e) => e.toString().trim())
            .where((String s) => s.isNotEmpty)
            .toList();
      } else if (data['allowedScreens'] is String) {
        parsedScreens = data['allowedScreens']
            .toString()
            .split(',')
            .map((s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toList();
      }
    }

    String? parsedScreen = data['screen']?.toString();
    if (parsedScreen != null &&
        parsedScreen.isNotEmpty &&
        !parsedScreens.contains(parsedScreen)) {
      if (parsedScreens.isEmpty) {
        parsedScreens.add(parsedScreen);
      }
    }
    if ((parsedScreen == null || parsedScreen.isEmpty) &&
        parsedScreens.isNotEmpty) {
      parsedScreen = parsedScreens.first;
    }

    // 2. Parse permissions / permission
    List<String> parsedPermissions = [];
    if (data['permissions'] != null) {
      if (data['permissions'] is List) {
        parsedPermissions = (data['permissions'] as List)
            .map((e) => e.toString().trim())
            .where((String s) => s.isNotEmpty)
            .toList();
      } else if (data['permissions'] is String) {
        parsedPermissions = data['permissions']
            .toString()
            .split(',')
            .map((s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toList();
      }
    } else if (data['permission'] != null) {
      if (data['permission'] is List) {
        parsedPermissions = (data['permission'] as List)
            .map((e) => e.toString().trim())
            .where((String s) => s.isNotEmpty)
            .toList();
      } else if (data['permission'] is String) {
        parsedPermissions = data['permission']
            .toString()
            .split(',')
            .map((s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toList();
      }
    }

    String? parsedPermission = data['permission']?.toString();
    if (parsedPermission != null &&
        parsedPermission.isNotEmpty &&
        !parsedPermissions.contains(parsedPermission)) {
      if (parsedPermissions.isEmpty) {
        parsedPermissions.add(parsedPermission);
      }
    }
    if ((parsedPermission == null || parsedPermission.isEmpty) &&
        parsedPermissions.isNotEmpty) {
      parsedPermission = parsedPermissions.first;
    }

    // 3. Parse screenPermissions
    Map<String, dynamic> parsedScreenPermissions = {};
    if (data['screenPermissions'] != null) {
      if (data['screenPermissions'] is Map) {
        parsedScreenPermissions = Map<String, dynamic>.from(data['screenPermissions']);
      } else if (data['screenPermissions'] is String) {
        try {
          final decoded = jsonDecode(data['screenPermissions']);
          if (decoded is Map) {
            parsedScreenPermissions = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
    }

    final String? parsedShareId = data['shareId']?.toString() ??
        data['params']?['shareId']?.toString() ??
        data['params']?['share_id']?.toString() ??
        data['params']?['s']?.toString() ??
        json['shareId']?.toString() ??
        json['s']?.toString();

    final rawParamsMap = Map<String, dynamic>.from(data['params'] ?? {});
    if (parsedShareId != null && parsedShareId.isNotEmpty) {
      rawParamsMap['shareId'] = parsedShareId;
      rawParamsMap['share_id'] = parsedShareId;
    }

    return AttributionResult(
      success: json['success'] ?? false,
      method: json['method'],
      clickId: data['clickId'],
      referralCode: json['referralCode'] ?? data['referralCode'],
      referralUserId: data['referralUserId'],
      referralFcmToken: data['referralFcmToken'],
      customReferrer: data['customReferrer'],
      shareId: parsedShareId,
      isInstall: data['is_install'] ?? false,
      attributionScore: data['attributionScore'],
      screen: parsedScreen,
      screens: parsedScreens,
      allowedScreens: parsedScreens,
      permission: parsedPermission,
      permissions: parsedPermissions,
      screenPermissions: parsedScreenPermissions,
      rawParams: rawParamsMap,
    );
  }

  @override
  String toString() {
    return 'AttributionResult(success: $success, method: $method, clickId: $clickId, referralCode: $referralCode, isInstall: $isInstall, screen: $screen, screens: $screens, permissions: $permissions, screenPermissions: $screenPermissions)';
  }
}


/// Represents a real-time permission update delivered to the client via push notification (FCM)
/// or retrieved live from the backend for a specific [shareId].
class SharePermissionUpdate {
  final String shareId;
  final String? linkId;
  final String? permission;
  final List<String> permissions;
  final String? screen;
  final List<String> screens;
  final Map<String, dynamic> screenPermissions;
  final String? productId;
  final String? url;
  final DateTime? updatedAt;
  final Map<String, dynamic> rawData;

  SharePermissionUpdate({
    required this.shareId,
    this.linkId,
    this.permission,
    List<String>? permissions,
    this.screen,
    List<String>? screens,
    Map<String, dynamic>? screenPermissions,
    this.productId,
    this.url,
    this.updatedAt,
    required this.rawData,
  })  : permissions = permissions ?? (permission != null && permission.isNotEmpty ? [permission] : []),
        screens = screens ?? (screen != null && screen.isNotEmpty ? [screen] : []),
        screenPermissions = screenPermissions ?? {};

  /// Checks if a global permission or any screen permission grants [permissionName].
  bool hasPermission(String permissionName) {
    if (permissions.contains(permissionName)) return true;
    for (final entry in screenPermissions.values) {
      if (entry is List && entry.contains(permissionName)) return true;
      if (entry is String && entry == permissionName) return true;
    }
    return false;
  }

  /// Checks if a specific screen allows [permissionName].
  bool hasScreenPermission(String screenName, String permissionName) {
    if (permissions.contains(permissionName)) return true;
    final screenPerm = screenPermissions[screenName];
    if (screenPerm is List) {
      return screenPerm.contains(permissionName);
    } else if (screenPerm is String) {
      return screenPerm == permissionName;
    }
    return false;
  }

  /// Checks if [screenName] is in the list of allowed/target screens.
  bool allowsScreen(String screenName) {
    if (screens.isEmpty) return true;
    return screens.contains(screenName);
  }

  factory SharePermissionUpdate.fromMap(Map<String, dynamic> data) {
    final shareId = data["shareId"]?.toString() ??
        data["share_id"]?.toString() ??
        data["params"]?["shareId"]?.toString() ??
        "";

    final linkId = data["linkId"]?.toString() ?? data["link_id"]?.toString();

    // 1. Permissions parsing
    List<String> parsedPermissions = [];
    final rawPerms = data["permissions"];
    if (rawPerms != null) {
      if (rawPerms is List) {
        parsedPermissions = rawPerms.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      } else if (rawPerms is String) {
        try {
          final decoded = jsonDecode(rawPerms);
          if (decoded is List) {
            parsedPermissions = decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
          } else {
            parsedPermissions = rawPerms.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          }
        } catch (_) {
          parsedPermissions = rawPerms.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
      }
    }

    final singlePerm = data["permission"]?.toString();
    if (singlePerm != null && singlePerm.isNotEmpty && !parsedPermissions.contains(singlePerm)) {
      parsedPermissions.insert(0, singlePerm);
    }

    // 2. Screens parsing
    List<String> parsedScreens = [];
    final rawScreens = data["screens"] ?? data["allowedScreens"];
    if (rawScreens != null) {
      if (rawScreens is List) {
        parsedScreens = rawScreens.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      } else if (rawScreens is String) {
        try {
          final decoded = jsonDecode(rawScreens);
          if (decoded is List) {
            parsedScreens = decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
          } else {
            parsedScreens = rawScreens.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          }
        } catch (_) {
          parsedScreens = rawScreens.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
      }
    }

    final singleScreen = data["screen"]?.toString();
    if (singleScreen != null && singleScreen.isNotEmpty && !parsedScreens.contains(singleScreen)) {
      parsedScreens.insert(0, singleScreen);
    }

    // 3. Screen permissions map parsing
    Map<String, dynamic> parsedScreenPerms = {};
    final rawScreenPerms = data["screenPermissions"];
    if (rawScreenPerms != null) {
      if (rawScreenPerms is Map) {
        parsedScreenPerms = Map<String, dynamic>.from(rawScreenPerms);
      } else if (rawScreenPerms is String) {
        try {
          final decoded = jsonDecode(rawScreenPerms);
          if (decoded is Map) {
            parsedScreenPerms = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
    }

    DateTime? parsedDate;
    if (data["updatedAt"] != null) {
      parsedDate = DateTime.tryParse(data["updatedAt"].toString());
    }

    return SharePermissionUpdate(
      shareId: shareId,
      linkId: linkId,
      permission: singlePerm,
      permissions: parsedPermissions,
      screen: singleScreen,
      screens: parsedScreens,
      screenPermissions: parsedScreenPerms,
      productId: data["productId"]?.toString() ?? data["product_id"]?.toString(),
      url: data["url"]?.toString(),
      updatedAt: parsedDate,
      rawData: Map<String, dynamic>.from(data),
    );
  }

  @override
  String toString() {
    return "SharePermissionUpdate(shareId: $shareId, permissions: $permissions, screens: $screens, screenPermissions: $screenPermissions)";
  }
}
