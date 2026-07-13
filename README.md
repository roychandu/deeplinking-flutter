# `deeplinking` Flutter SDK

A lightweight, developer-first, self-hosted Mobile Measurement Partner (MMP) and attribution package for Flutter. Connects app clicks to app installs, captures P2P referrals, and routes installs to contextual screens.

## Installation

Add the package dependency to your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  deeplinking:
    path: ../deeplinking-flutter # Or your hosted git URL
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
import 'package:deeplinking/deeplinking.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure with your self-hosted Link Traker Vercel server URL
  LinkTraker.configure(
    baseUrl: 'https://your-app.vercel.app',
    appId: 'your_unique_app_id',
  );

  runApp(const MyApp());
}
```

---

## Usage Guide

### 2. Auto-Attuning Installs (Deferred Deep Linking)
When the app launches for the first time, check if the install originated from a tracking link. This will automatically read the click ID from the clipboard or fall back to IP-based fingerprinting.

```dart
void checkAttribution() async {
  final result = await LinkTraker.trackInstall(
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
}
```

### 3. Redeeming Referrals & Granting Rewards
When a referred user completes onboarding or registers, call this method to trigger referral rewards. This fires FCM notifications to the referrer and returns the dynamic reward settings.

```dart
void redeemUserReferral(String referralCode) async {
  try {
    final response = await LinkTraker.redeemReferral(
      referralCode: referralCode,
      newUserId: 'NEW_USER_456', // The new user who just signed up
      rewardDays: 15, // Dynamic reward overwrite (optional)
    );

    if (response['success'] == true) {
      final rewardDays = response['rewardDays'];
      print('Referral redeemed! Credited $rewardDays days of premium.');
    }
  } catch (e) {
    print('Redeem failed: $e');
  }
}
```

### 4. Tracking Shares (Virality Rankings)
Log sharing activity immediately before opening the OS Share Sheet. This contributes to your analytics for most-shared screens and products.

```dart
void onShareProductClicked() async {
  await LinkTraker.trackShare(
    linkId: 'TRACKING_LINK_ID',
    referralCode: 'SENDER_REF_CODE',
    screen: 'product_details_screen',
    source: 'WhatsApp', // WhatsApp, Telegram, copy_link, etc.
    params: {
      'productId': 'prod_999',
      'price': 49.99
    }
  );
}
```
