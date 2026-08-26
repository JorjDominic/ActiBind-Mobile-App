class InsightMetrics {
  const InsightMetrics({
    required this.todayValue,
    required this.todayLabel,
    required this.dailyAverage,
    required this.previousDailyAverage,
    required this.averageChangePercent,
    required this.goalProgress,
    required this.dayLevels,
    required this.dayDurations,
    required this.peakWindow,
    required this.phoneToday,
    required this.pcToday,
    required this.connectedDeviceCount,
    required this.overLimitAppCount,
    required this.topApps,
  });

  final Duration todayValue;
  final String todayLabel;
  final Duration dailyAverage;
  final Duration previousDailyAverage;
  final double? averageChangePercent;
  final double goalProgress;
  final List<double> dayLevels;
  final List<Duration> dayDurations;
  final String peakWindow;
  final Duration phoneToday;
  final Duration pcToday;
  final int connectedDeviceCount;
  final int overLimitAppCount;
  final List<InsightAppMetric> topApps;
}

class InsightAppMetric {
  const InsightAppMetric({
    required this.name,
    required this.duration,
    required this.source,
  });

  final String name;
  final Duration duration;
  final String source;
}
