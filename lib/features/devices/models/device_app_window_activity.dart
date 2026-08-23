class DeviceAppWindowActivity {
  const DeviceAppWindowActivity({
    required this.windowTitle,
    required this.totalSeconds,
  });

  final String windowTitle;
  final int totalSeconds;

  factory DeviceAppWindowActivity.fromJson(Map<String, dynamic> json) {
    final seconds = json['total_seconds'];
    return DeviceAppWindowActivity(
      windowTitle: (json['window_title'] as String).trim(),
      totalSeconds: seconds is int ? seconds : int.parse(seconds.toString()),
    );
  }
}
