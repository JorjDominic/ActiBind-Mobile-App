abstract final class AppNameService {
  static const _officialNames = <String, String>{
    'chrome': 'Google Chrome',
    'google chrome': 'Google Chrome',
    'msedge': 'Microsoft Edge',
    'microsoft edge': 'Microsoft Edge',
    'firefox': 'Mozilla Firefox',
    'brave': 'Brave',
    'brave browser': 'Brave',
    'opera': 'Opera',
    'opera gx': 'Opera GX',
    'code': 'Visual Studio Code',
    'visual studio code': 'Visual Studio Code',
    'devenv': 'Microsoft Visual Studio',
    'discord': 'Discord',
    'slack': 'Slack',
    'teams': 'Microsoft Teams',
    'ms-teams': 'Microsoft Teams',
    'spotify': 'Spotify',
    'steam': 'Steam',
    'epicgameslauncher': 'Epic Games Launcher',
    'vlc': 'VLC media player',
    'winword': 'Microsoft Word',
    'excel': 'Microsoft Excel',
    'powerpnt': 'Microsoft PowerPoint',
    'outlook': 'Microsoft Outlook',
    'onenote': 'Microsoft OneNote',
    'notepad': 'Notepad',
    'explorer': 'File Explorer',
    'photos': 'Microsoft Photos',
    'applicationframehost': 'Microsoft Store app',
  };

  static String officialName(String appName, [String packageName = '']) {
    for (final candidate in [appName, packageName]) {
      final normalized = candidate
          .trim()
          .replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '')
          .toLowerCase();
      final official = _officialNames[normalized];
      if (official != null) return official;
    }
    final cleaned = appName.trim().replaceFirst(
      RegExp(r'\.exe$', caseSensitive: false),
      '',
    );
    return cleaned.isEmpty ? 'Unknown app' : cleaned;
  }
}
