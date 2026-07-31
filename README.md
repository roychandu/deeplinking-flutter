# `deeplinking` Flutter SDK

A lightweight, developer-first, self-hosted Mobile Measurement Partner (MMP) and attribution package for Flutter. Connects app clicks to app installs, captures P2P referrals, and routes installs to contextual screens.

## Installation

Add `deeplinking` to your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  deeplinking: ^1.0.0
```

And run:
```bash
flutter pub get
```

---

## Getting Started

### 1. Initialize the SDK
Configure the SDK when your app starts (typically in `lib/main.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:deeplinking/deeplinking.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure with your server base URL, registered App ID, and Workspace SDK Key
  DeepLinking.configure(
    baseUrl: 'https://deeplinking.in',
    appId: 'com.example.store_room',
    sdkKey: 'dlk_live_xxxxxxxxxxxxxxxxxxxxxxxx',
  );

  runApp(const MyApp());
}
```

---

## Usage Guide

### 2. Auto-Attributing Installs (Deferred Deep Linking)
When the app launches for the first time, check if the install originated from a tracking link. This will automatically read the click ID from the clipboard or fall back to IP-based fingerprinting.

```dart
void checkAttribution(BuildContext context) async {
  try {
    final result = await DeepLinking.trackInstall(
      linkId: 'FALLBACK_LINK_ID', // Used for fingerprint matching
      installerFcmToken: 'USER_FCM_TOKEN', // Send to enable push notifications
      installerUserId: 'USER_123', // User ID inside your system
    );

    if (result != null && result.success) {
      print('Successfully attributed install!');
      print('Method: ${result.method}'); // 'direct' or 'fingerprint'
      print('Referral Code: ${result.referralCode}');
      print('Allowed Screens: ${result.allowedScreens}');
      
      // Check if the link restricts which screens they can see:
      if (result.allowedScreens.contains('promo_screen')) {
        // Navigate user to the promo screen
      }
    } else {
      print('Organic install / No attribution matches.');
    }
  } on SdkLimitExceededException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  } on InvalidSdkKeyException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
```

### 3. Redeeming Referrals & Granting Rewards
When a referred user completes onboarding or registers, call this method to trigger referral rewards. This fires FCM notifications to the referrer and returns the dynamic reward settings.

```dart
void redeemUserReferral(BuildContext context, String referralCode) async {
  try {
    final response = await DeepLinking.redeemReferral(
      referralCode: referralCode,
      newUserId: 'NEW_USER_456', // The new user who just signed up
      rewardDays: 15, // Dynamic reward overwrite (optional)
    );

    if (response['success'] == true) {
      final rewardDays = response['rewardDays'];
      print('Referral redeemed! Credited $rewardDays days of premium.');
    }
  } on SdkLimitExceededException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  } on InvalidSdkKeyException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
```

### 4. Tracking Shares & CTA Actions
Log sharing activity immediately before opening the OS Share Sheet. This contributes to your analytics for most-shared screens and products.

```dart
void onShareProductClicked(BuildContext context) async {
  try {
    await DeepLinking.trackShare(
      linkId: 'TRACKING_LINK_ID',
      referralCode: 'SENDER_REF_CODE',
      screen: 'product_details_screen',
      eventId: 'share_evt_123',
      params: {
        'productId': 'prod_999',
        'price': 49.99
      }
    );
  } on SdkLimitExceededException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  } on InvalidSdkKeyException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
```

---

## Exception Handling

All gated SDK methods throw dedicated typed exceptions on failure:

- **`SdkLimitExceededException`**: Thrown when monthly plan quota is exhausted (`HTTP 429`).
- **`InvalidSdkKeyException`**: Thrown when SDK key is invalid, missing, or app ID is not registered (`HTTP 401/403`).

