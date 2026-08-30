import 'package:actibind/core/settings/privacy_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('sensitive AI sources are disabled by default', () async {
    SharedPreferences.setMockInitialValues({});
    await PrivacyController.instance.load();

    expect(PrivacyController.instance.includeDeviceActivity, isTrue);
    expect(PrivacyController.instance.includeBrowserTitles, isFalse);
    expect(PrivacyController.instance.includeNotes, isFalse);
    expect(PrivacyController.instance.includeFamilyProfiles, isFalse);
  });

  test('disabling device activity also disables browser titles', () async {
    SharedPreferences.setMockInitialValues({
      'privacy_device_activity': true,
      'privacy_browser_titles': true,
    });
    await PrivacyController.instance.load();
    await PrivacyController.instance.setValue('device_activity', false);

    expect(PrivacyController.instance.includeDeviceActivity, isFalse);
    expect(PrivacyController.instance.includeBrowserTitles, isFalse);
  });
}
