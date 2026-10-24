import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// What phone the rider uses; sent with the rider record.
class PhoneInfo {
  const PhoneInfo({this.model, this.osVersion});

  final String? model;
  final String? osVersion;

  static const unknown = PhoneInfo();
}

typedef PhoneInfoReader = Future<PhoneInfo> Function();

Future<PhoneInfo> readPhoneInfo() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final a = await plugin.androidInfo;
      return PhoneInfo(
        model: '${a.manufacturer} ${a.model}'.trim(),
        osVersion: 'Android ${a.version.release}',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final i = await plugin.iosInfo;
      return PhoneInfo(
        model: i.utsname.machine,
        osVersion: '${i.systemName} ${i.systemVersion}',
      );
    }
  } catch (_) {}
  return PhoneInfo.unknown;
}
