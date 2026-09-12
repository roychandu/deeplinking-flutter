# `deeplinking` Flutter SDK

A lightweight, developer-first, self-hosted Mobile Measurement Partner (MMP) and attribution package for Flutter. Connects app clicks to app installs, captures P2P referrals, supports multi-screen routing, and enforces granular per-screen permissions.

## Features

- **Deferred Deep Linking**: 100% deterministic attribution via clipboard matching + probabilistic fingerprinting fallback.
- **Multiple Target Screens**: Direct users to multiple accessible screens (`screens` / `allowedScreens`).
- **Granular Permissions**: Global permissions (`permissions`) and per-screen capability scoping (`screenPermissions`).
- **P2P Referral Engine**: Built-in reward crediting and FCM push sync for referrers and invitees.
- **Native Direct Intent Routing**: Seamless handling for cold-start and warm-start deep link intents.

---

## Installation

Add `deeplinking` to your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  deeplinking: ^1.0.1
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
      print('Target Screens: ${result.screens}');
      print('Granted Permissions: ${result.permissions}');
      print('Per-Screen Permissions: ${result.screenPermissions}');
      
      // Check if user is allowed to access a specific screen:
      if (result.allowsScreen('PromoScreen')) {
        Navigator.of(context).pushNamed('/promo');
      }

      // Check if user has a global or screen-specific permission:
      if (result.hasScreenPermission('ProductDetail', 'buy')) {
        // Enable direct purchase button
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

### 3. Registering & Generating Multi-Screen Share Links
Generate personalized share links with multiple accessible screens and granular per-screen permissions:

```dart
void generateMultiScreenShare() async {
  try {
    final response = await DeepLinking.registerShare(
      linkId: 'PROMO_LINK_ID',
      screens: ['Catalog', 'ProductDetail', 'Cart'],
      permissions: ['read', 'comment', 'vip_access'],
      screenPermissions: {
        'ProductDetail': ['view_price', 'add_to_cart'],
        'Cart': ['apply_coupon'],
      },
      senderReferralCode: 'ALICE100',
      senderUserId: 'user_alice',
      productId: 'shoe_123',
    );

    final shareUrl = response['shareUrl'];
    print('Generated Share Link: $shareUrl');
  } catch (e) {
    print('Error registering share: $e');
  }
}
```


### 4. Branded URL Shortener & P2P Sharing
Generate clean, branded short URLs (`https://yourdomain.com/s/:code`) instead of sharing long URLs with query parameters:

#### Option A: Automatic Short Link with `registerShare` (Recommended for P2P Sharing)
When registering a share with user referral codes, target screens, or permissions, `registerShare` automatically provisions a branded short link:

```dart
void shareReferralInvite() async {
  try {
    final response = await DeepLinking.registerShare(
      linkId: 'LINK_ID',
      senderReferralCode: 'ALICE100',
      senderUserId: 'user_123',
      senderFcmToken: 'USER_FCM_TOKEN',
      screen: 'ProductDetail',
    );

    // Clean, compact short link ready for WhatsApp / SMS:
    final shortUrl = response['shortUrl']; // e.g. https://deeplinking.in/s/7vNkoGn
    print('Share via WhatsApp: $shortUrl');
  } catch (e) {
    print('Error registering share: $e');
  }
}
```

#### Option B: Standalone Link Shortening with `shortenLink`
Generate a branded short URL for any master tracking link, with an optional custom vanity alias or custom domain:

```dart
void generateShortLink() async {
  try {
    final response = await DeepLinking.shortenLink(
      linkId: 'YOUR_LINK_ID',
      customCode: 'summer-sale', // Optional vanity slug: /s/summer-sale
      customDomain: 'links.example.com', // Optional custom domain
    );

    final shortUrl = response['shortUrl']; // e.g. https://links.example.com/s/summer-sale
    print('Short URL: $shortUrl');
  } catch (e) {
    print('Error shortening link: $e');
  }
}
```

### 5. Listening for Direct Deep Links (Native App Links)
Listen for deep link open events when the app is already installed:

```dart
@override
void initState() {
  super.initState();

  DeepLinking.onDeepLinkOpen((params) {
    print('Deep link opened natively: $params');
    final screen = params['screen'];
    final screens = params['screens'];
    final permissions = params['permissions'];
    // Route user accordingly...
  });
}
```

### 6. Redeeming Referrals & Granting Rewards
When a referred user completes onboarding or registers, call this method to trigger referral rewards. This fires FCM notifications to the referrer and returns the dynamic reward settings:

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

### 7. Tracking Shares & CTA Actions
Log sharing activity immediately before opening the OS Share Sheet. This contributes to your analytics for most-shared screens and products:

```dart
void onShareProductClicked(BuildContext context) async {
  try {
    await DeepLinking.trackShare(
      linkId: 'TRACKING_LINK_ID',
      referralCode: 'SENDER_REF_CODE',
      screens: ['ProductDetail', 'Checkout'],
      permissions: ['view', 'buy'],
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

---

## License

MIT
