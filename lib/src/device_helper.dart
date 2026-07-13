import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceHelper {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static Future<Map<String, String>> getDeviceInfo() async {
    Map<String, String> info = {
      'osName': 'Unknown',
      'osVersion': 'Unknown',
      'deviceModel': 'Unknown',
    };

    try {
      if (kIsWeb) {
        info['osName'] = 'Web';
        final webBrowserInfo = await _deviceInfo.webBrowserInfo;
        info['osVersion'] = webBrowserInfo.userAgent ?? 'Unknown';
        info['deviceModel'] = webBrowserInfo.browserName.name;
      } else if (Platform.isAndroid) {
        info['osName'] = 'Android';
        final androidInfo = await _deviceInfo.androidInfo;
        info['osVersion'] = androidInfo.version.release;
        info['deviceModel'] =
            '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        info['osName'] = 'iOS';
        final iosInfo = await _deviceInfo.iosInfo;
        info['osVersion'] = iosInfo.systemVersion;
        info['deviceModel'] = iosInfo.model;
      } else if (Platform.isMacOS) {
        info['osName'] = 'macOS';
        final macInfo = await _deviceInfo.macOsInfo;
        info['osVersion'] = '${macInfo.majorVersion}.${macInfo.minorVersion}';
        info['deviceModel'] = macInfo.model;
      }
    } catch (e) {
      // Silently fall back if gathering fails
    }

    return info;
  }
}
