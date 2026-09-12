## 1.0.1

* **Branded URL Shortener**: Added `DeepLinking.shortenLink(...)` to generate clean, branded short URLs (`https://domain/s/:code`) for any tracking link or share with optional custom vanity code and custom domain.
* **P2P Referral Short Links**: `DeepLinking.registerShare(...)` now returns `shortUrl` (`response['shortUrl']`) directly, allowing clean invite links for WhatsApp/SMS without cumbersome query strings.
* **Improved Clipboard Short Link Resolution**: Resolved short links (`/s/:code`) in `trackInstall` without overwriting the master `linkId`, ensuring seamless install attribution and deferred deep linking.
* **Push Notification Sync**: Automatic binding between shortened referral links, sender FCM tokens, and instant referral reward push notifications upon redemption.
* Added real-time permission update support via FCM push notifications.
* Introduced `SharePermissionUpdate` model for parsing and handling live permission changes.
* Added `DeepLinking.onPermissionUpdated` callback and `DeepLinking.permissionUpdates` stream.
* Added `DeepLinking.permissionUpdateNotifier` for reactive UI binding via `ValueListenableBuilder`.
* Added `DeepLinking.handleNotificationData(data)` to parse incoming FCM payloads.
* Extended `DeepLinking.updateShare` with `notifySender`, `notificationTitle`, `notificationBody`, and `silent` options.
* Added support for **Multiple Target Screens** (`screens`, `allowedScreens`) in attribution and share registration.
* Added support for **Multiple Permissions** (`permissions`, `permission`) and granular **Per-Screen Permissions** (`screenPermissions`).
* Added helper query methods to `AttributionResult`: `hasPermission()`, `hasScreenPermission()`, and `allowsScreen()`.
* Enhanced clipboard parser to extract multiple screens (`__scrs_`, `__als_`), permissions (`__perms_`), and granular screen permissions (`__sperms_`).
* Updated native Android intent listener to extract and persist `screens`, `allowedScreens`, `permissions`, and `screenPermissions`.
* 100% backward compatibility maintained for existing single `screen` and single `permission` integrations.

## 1.0.0

* Initial release of the `deeplinking` Flutter SDK.
* Automated install attribution (Direct Clipboard and Fingerprinting matching).
* P2P Referral rewards validation.
* Native share tracking integration.
