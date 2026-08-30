import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrivacyController extends ChangeNotifier {
  PrivacyController._();

  static final instance = PrivacyController._();
  static const _prefix = 'privacy_';

  bool includeDeviceActivity = true;
  bool includeBrowserTitles = false;
  bool includeNotes = false;
  bool includeFamilyProfiles = false;
  bool includeWeather = true;
  bool includeHolidays = true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    includeDeviceActivity = prefs.getBool('${_prefix}device_activity') ?? true;
    includeBrowserTitles = prefs.getBool('${_prefix}browser_titles') ?? false;
    includeNotes = prefs.getBool('${_prefix}notes') ?? false;
    includeFamilyProfiles = prefs.getBool('${_prefix}family_profiles') ?? false;
    includeWeather = prefs.getBool('${_prefix}weather') ?? true;
    includeHolidays = prefs.getBool('${_prefix}holidays') ?? true;
    notifyListeners();
  }

  Future<void> setValue(String key, bool value) async {
    switch (key) {
      case 'device_activity':
        includeDeviceActivity = value;
        if (!value) includeBrowserTitles = false;
        break;
      case 'browser_titles':
        includeBrowserTitles = value;
        break;
      case 'notes':
        includeNotes = value;
        break;
      case 'family_profiles':
        includeFamilyProfiles = value;
        break;
      case 'weather':
        includeWeather = value;
        break;
      case 'holidays':
        includeHolidays = value;
        break;
      default:
        throw ArgumentError.value(key, 'key');
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$key', value);
    if (key == 'device_activity' && !value) {
      await prefs.setBool('${_prefix}browser_titles', false);
    }
  }
}
