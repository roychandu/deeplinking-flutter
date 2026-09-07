## 1.0.1

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
