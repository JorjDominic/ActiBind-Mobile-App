import 'package:actibind/features/devices/services/app_name_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses official names for common PC executables', () {
    expect(AppNameService.officialName('chrome.exe'), 'Google Chrome');
    expect(AppNameService.officialName('msedge.exe'), 'Microsoft Edge');
    expect(AppNameService.officialName('Code.exe'), 'Visual Studio Code');
    expect(AppNameService.officialName('WINWORD.EXE'), 'Microsoft Word');
  });

  test('removes the executable suffix from unknown app names', () {
    expect(AppNameService.officialName('MyProduct.exe'), 'MyProduct');
  });
}
