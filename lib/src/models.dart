class AttributionResult {
  final bool success;
  final String? method;
  final String? clickId;
  final String? referralCode;
  final String? referralUserId;
  final String? referralFcmToken;
  final String? customReferrer;
  final bool isInstall;
  final int? attributionScore;
  final String? permission;
  final List<String> allowedScreens;
  final Map<String, dynamic> rawParams;

  AttributionResult({
    required this.success,
    this.method,
    this.clickId,
    this.referralCode,
    this.referralUserId,
    this.referralFcmToken,
    this.customReferrer,
    required this.isInstall,
    this.attributionScore,
    this.permission,
    required this.allowedScreens,
    required this.rawParams,
  });

  factory AttributionResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};

    // Parse allowedScreens
    List<String> screens = [];
    if (data['allowedScreens'] != null) {
      if (data['allowedScreens'] is List) {
        screens = List<String>.from(data['allowedScreens']);
      }
    }

    return AttributionResult(
      success: json['success'] ?? false,
      method: json['method'],
      clickId: data['clickId'],
      referralCode: json['referralCode'] ?? data['referralCode'],
      referralUserId: data['referralUserId'],
      referralFcmToken: data['referralFcmToken'],
      customReferrer: data['customReferrer'],
      isInstall: data['is_install'] ?? false,
      attributionScore: data['attributionScore'],
      permission: data['permission'],
      allowedScreens: screens,
      rawParams: Map<String, dynamic>.from(data['params'] ?? {}),
    );
  }

  @override
  String toString() {
    return 'AttributionResult(success: $success, method: $method, clickId: $clickId, referralCode: $referralCode, isInstall: $isInstall, allowedScreens: $allowedScreens)';
  }
}
