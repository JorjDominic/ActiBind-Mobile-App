import 'dart:async';
import 'dart:typed_data';

import 'package:actibind/core/constants/app_constants.dart';
import 'package:actibind/core/settings/daily_summary_controller.dart';
import 'package:actibind/core/theme/app_colors.dart';
import 'package:actibind/features/activities/models/app_usage.dart';
import 'package:actibind/features/activities/models/activity.dart';
import 'package:actibind/features/activities/services/activity_service.dart';
import 'package:actibind/features/activities/services/usage_stats_service.dart';
import 'package:actibind/features/insights/services/insight_service.dart';
import 'package:actibind/features/insights/models/insight_metrics.dart';
import 'package:actibind/features/insights/services/insight_metrics_service.dart';
import 'package:actibind/features/weather/models/current_weather.dart';
import 'package:actibind/features/weather/services/weather_service.dart';
import 'package:actibind/features/weather/services/reverse_geocoding_service.dart';
import 'package:actibind/shared/widgets/app_page_header.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shad;

class HomeOverviewPage extends StatefulWidget {
  const HomeOverviewPage({
    super.key,
    required this.displayName,
    required this.onAddActivity,
    required this.onAddRoutine,
  });

  final String displayName;
  final VoidCallback onAddActivity;
  final VoidCallback onAddRoutine;

  @override
  State<HomeOverviewPage> createState() => _HomeOverviewPageState();
}

class _HomeOverviewPageState extends State<HomeOverviewPage> {
  InsightMetrics? _metrics;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    try {
      final metrics = await InsightMetricsService.load(days: 7);
      if (mounted) setState(() => _metrics = metrics);
    } catch (_) {
      // Individual overview cards retain a safe loading state.
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'GOOD MORNING';
    if (hour >= 12 && hour < 17) return 'GOOD AFTERNOON';
    if (hour >= 17 && hour < 22) return 'GOOD EVENING';
    return 'GOOD NIGHT';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppPageHeader(
            title: 'Overview',
            subtitle: 'Your devices, plans, routines, and next actions',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.indigo, Color(0xFF7779EA), AppColors.teal],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.indigo.withValues(alpha: .14),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Make today count, ${widget.displayName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _metrics == null
                            ? 'Syncing your planned-time share…'
                            : '${(_metrics!.goalProgress * 100).round()}% of today’s recorded device time is covered by elapsed plans.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CircularProgressIndicator(
                          value: _metrics?.goalProgress ?? 0,
                          strokeWidth: 6,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      Text(
                        '${((_metrics?.goalProgress ?? 0) * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _WeatherCard(),
          const SizedBox(height: 18),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    title: 'Device use today',
                    value: _metrics == null
                        ? '—'
                        : InsightMetricsService.formatDuration(
                            _metrics!.todayValue,
                          ),
                    subtitle: 'phone + PC',
                    color: AppColors.indigo,
                  ),
                ),
                const VerticalDivider(width: 24, thickness: 1),
                const Expanded(child: _ConflictSummaryTile()),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const AppSectionHeader(
            title: 'Quick Actions',
            subtitle: 'Keep your day moving',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, _) => GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 76,
              children: [
                _ActionCard(
                  icon: Icons.event_note_rounded,
                  title: 'Activity',
                  color: AppColors.indigo,
                  onTap: widget.onAddActivity,
                ),
                _ActionCard(
                  icon: Icons.repeat_rounded,
                  title: 'Routine',
                  color: AppColors.teal,
                  onTap: widget.onAddRoutine,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _TopActivity(),
          AnimatedBuilder(
            animation: DailySummaryController.instance,
            builder: (context, _) {
              if (!DailySummaryController.instance.enabled) {
                return const SizedBox.shrink();
              }
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 24),
                  AppSectionHeader(
                    title: 'Your latest insight',
                    subtitle:
                        'A pattern worth knowing from your recent activity',
                  ),
                  SizedBox(height: 12),
                  _AiHomeInsight(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AiHomeInsight extends StatefulWidget {
  const _AiHomeInsight();

  @override
  State<_AiHomeInsight> createState() => _AiHomeInsightState();
}

class _AiHomeInsightState extends State<_AiHomeInsight> {
  String? _insight;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final insight = await InsightService.generateHomeInsight();
      if (mounted) setState(() => _insight = insight);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppColors.teal.withValues(alpha: .13),
          AppColors.indigo.withValues(alpha: .09),
        ],
      ),
      border: Border.all(color: AppColors.teal.withValues(alpha: .18)),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.auto_awesome_rounded, color: AppColors.teal),
        const SizedBox(width: 11),
        Expanded(
          child: _loading && _insight == null
              ? const LinearProgressIndicator()
              : Text(
                  _failed && _insight == null
                      ? 'AI insight is unavailable right now. Tap retry to try again.'
                      : _insight!,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
        ),
        if (_failed || _insight != null)
          IconButton(
            tooltip: _failed ? 'Retry insight' : 'Refresh insight',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    ),
  );
}

class _WeatherCard extends StatefulWidget {
  const _WeatherCard();

  @override
  State<_WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<_WeatherCard> {
  CurrentWeather? _weather;
  String? _weatherTip;
  bool _loading = true;
  bool _failed = false;
  bool _tipLoading = false;
  bool _usingFallbackLocation = false;
  String _locationName = 'Manila';
  int _tipRequest = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    Position? position;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are disabled.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was denied.');
      }
      final lastKnown = await Geolocator.getLastKnownPosition();
      final recentEnough =
          !forceRefresh &&
          lastKnown != null &&
          DateTime.now().difference(lastKnown.timestamp) <
              const Duration(minutes: 30) &&
          lastKnown.accuracy <= 1000;
      if (recentEnough) {
        position = lastKnown;
      } else {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 20),
            ),
          );
        } catch (_) {
          position = lastKnown;
        }
      }
    } catch (_) {
      // Devices without a GPS fix still receive useful Manila weather.
    }
    try {
      final usingFallback = position == null;
      final latitude = position?.latitude ?? 14.5995;
      final longitude = position?.longitude ?? 120.9842;
      final results = await Future.wait<Object?>([
        WeatherService.getCurrentWeather(
          latitude: latitude,
          longitude: longitude,
          forceRefresh: forceRefresh,
        ),
        position == null
            ? Future<String?>.value('Manila')
            : _resolveLocationName(position),
      ]);
      final weather = results[0] as CurrentWeather;
      final locationName =
          results[1] as String? ??
          '${latitude.toStringAsFixed(2)}, ${longitude.toStringAsFixed(2)}';
      if (mounted) {
        setState(() {
          _weather = weather;
          _usingFallbackLocation = usingFallback;
          _locationName = locationName;
        });
        unawaited(_loadWeatherTip(weather, locationName));
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadWeatherTip(
    CurrentWeather weather,
    String locationName,
  ) async {
    final request = ++_tipRequest;
    if (mounted) setState(() => _tipLoading = true);
    try {
      final tip = await InsightService.generateWeatherTip(
        weather: weather,
        location: locationName,
      );
      if (mounted && request == _tipRequest) {
        setState(() => _weatherTip = tip);
      }
    } catch (_) {
      // Keep the instant condition-based tip when AI is unavailable.
    } finally {
      if (mounted && request == _tipRequest) {
        setState(() => _tipLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final weather = _weather;
    return shad.Card(
      filled: true,
      fillColor: AppColors.teal.withValues(alpha: .06),
      borderColor: AppColors.teal.withValues(alpha: .18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: _loading && weather == null
            ? const LinearProgressIndicator()
            : _failed && weather == null
            ? Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, color: AppColors.muted),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Weather is unavailable.')),
                  IconButton(
                    tooltip: 'Retry weather',
                    onPressed: _loading
                        ? null
                        : () => _load(forceRefresh: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.teal.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _weatherIcon(weather!),
                          color: AppColors.teal,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_usingFallbackLocation ? '$_locationName fallback' : _locationName} · ${_condition(weather.weatherCode)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Feels like ${weather.apparentTemperature.round()}° · '
                              '${weather.humidity}% humidity · '
                              '${weather.windSpeed.round()} km/h wind',
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${weather.temperature.round()}°',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        tooltip: _loading
                            ? 'Refreshing weather'
                            : 'Refresh weather',
                        visualDensity: VisualDensity.compact,
                        onPressed: _loading
                            ? null
                            : () => _load(forceRefresh: true),
                        icon: _loading
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(
                    height: 1,
                    color: AppColors.teal.withValues(alpha: .15),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 16,
                        color: AppColors.teal,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _weatherTip ?? _fallbackInsight(weather),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (_tipLoading) ...[
                        const SizedBox(width: 8),
                        const SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  static String _condition(int code) {
    if (code == 0) return 'Clear';
    if (code <= 3) return 'Partly cloudy';
    if (code == 45 || code == 48) return 'Foggy';
    if (code <= 57) return 'Drizzle';
    if (code <= 67) return 'Rain';
    if (code <= 77) return 'Snow';
    if (code <= 82) return 'Rain showers';
    if (code <= 86) return 'Snow showers';
    return 'Thunderstorms';
  }

  static Future<String> _resolveLocationName(Position position) async {
    try {
      final onlineName = await ReverseGeocodingService.getCity(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (onlineName != null) return onlineName;
    } catch (_) {
      // Fall through to the platform geocoder.
    }
    try {
      final places = await Geocoding(locale: const Locale('en'))
          .placemarkFromCoordinates(position.latitude, position.longitude)
          .timeout(const Duration(seconds: 5));
      if (places.isNotEmpty) {
        final place = places.first;
        for (final value in [
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
        ]) {
          if (value != null && value.trim().isNotEmpty) return value.trim();
        }
      }
    } catch (_) {
      // Coordinates remain visible when the platform geocoder is unavailable.
    }
    return '${position.latitude.toStringAsFixed(2)}, '
        '${position.longitude.toStringAsFixed(2)}';
  }

  static String _fallbackInsight(CurrentWeather weather) {
    final code = weather.weatherCode;
    if (code >= 95) {
      return 'Thunderstorms are likely—use an indoor Focus session and postpone outdoor Workout activities.';
    }
    if (code >= 51 && code <= 82) {
      return 'Rain is in the area—move your Workout indoors and add travel time to Personal tasks.';
    }
    if (weather.temperature >= 33 || weather.apparentTemperature >= 36) {
      return 'Heat stress is possible—schedule Workout activities earlier and keep Focus sessions indoors.';
    }
    if (weather.windSpeed >= 35) {
      return 'Strong winds may disrupt outdoor tasks—switch your Workout or Personal activity indoors.';
    }
    if (code <= 1 && weather.isDay) {
      return 'Clear conditions make this a good window for your Workout or outdoor Personal tasks.';
    }
    if (!weather.isDay) {
      return 'Conditions suit a Wind-down routine; finish outdoor Personal tasks before it gets later.';
    }
    return 'Conditions are comfortable—your planned Focus, Workout, and Personal activities need minimal adjustment.';
  }

  static IconData _weatherIcon(CurrentWeather weather) {
    final code = weather.weatherCode;
    if (code == 0) {
      return weather.isDay ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded;
    }
    if (code <= 3) return Icons.cloud_queue_rounded;
    if (code == 45 || code == 48) return Icons.blur_on_rounded;
    if (code <= 57) return Icons.grain_rounded;
    if (code <= 82) return Icons.water_drop_rounded;
    return Icons.thunderstorm_rounded;
  }
}

class _TopActivity extends StatefulWidget {
  const _TopActivity();

  @override
  State<_TopActivity> createState() => _TopActivityState();
}

class _TopActivityState extends State<_TopActivity>
    with WidgetsBindingObserver {
  List<AppUsage> _usage = const [];
  bool _loading = true;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!UsageStatsService.isSupported) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final allowed = await UsageStatsService.hasPermission();
      var items = const <AppUsage>[];
      if (allowed) {
        final now = DateTime.now();
        items = await UsageStatsService.getUsage(
          start: DateTime(now.year, now.month, now.day),
          end: now,
        );
      }
      if (mounted) {
        setState(() {
          _allowed = allowed;
          _usage = items.take(3).toList(growable: false);
        });
      }
    } catch (_) {
      // Keep the overview usable if native usage data is temporarily unavailable.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AppSectionHeader(
        title: 'Top Activity',
        subtitle: 'Your three most-used apps today',
      ),
      const SizedBox(height: 12),
      if (_loading)
        const LinearProgressIndicator()
      else if (!_allowed)
        Text(
          UsageStatsService.isSupported
              ? 'Allow usage access in Activity to see your top apps.'
              : 'Top activity is available on Android.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        )
      else if (_usage.isEmpty)
        const Text('No app activity recorded today.')
      else
        shad.Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                for (var index = 0; index < _usage.length; index++) ...[
                  _TopActivityRow(rank: index + 1, usage: _usage[index]),
                  if (index != _usage.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ),
    ],
  );
}

class _TopActivityRow extends StatelessWidget {
  const _TopActivityRow({required this.rank, required this.usage});

  final int rank;
  final AppUsage usage;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '$rank',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        _HomeAppIcon(bytes: usage.iconBytes),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            usage.appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Text(_duration(usage.foreground)),
      ],
    ),
  );

  static String _duration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
  }
}

class _HomeAppIcon extends StatelessWidget {
  const _HomeAppIcon({required this.bytes});
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: AppColors.indigo.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(9),
    ),
    child: bytes == null
        ? const Icon(Icons.apps_rounded, size: 20, color: AppColors.indigo)
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes!,
              cacheWidth: 48,
              cacheHeight: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.apps_rounded,
                size: 20,
                color: AppColors.indigo,
              ),
            ),
          ),
  );
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ConflictSummaryTile extends StatefulWidget {
  const _ConflictSummaryTile();

  @override
  State<_ConflictSummaryTile> createState() => _ConflictSummaryTileState();
}

class _ConflictSummaryTileState extends State<_ConflictSummaryTile> {
  List<Activity>? _conflicts;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    try {
      final conflicts = await ActivityService.getConflictingActivitiesInRange(
        from: today,
        to: today.add(const Duration(days: 1)),
      );
      if (mounted) setState(() => _conflicts = conflicts);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _handleTap() async {
    if (_failed) {
      await _load();
      return;
    }
    final conflicts = _conflicts;
    if (conflicts == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          conflicts.isEmpty
              ? Icons.event_available_rounded
              : Icons.warning_amber_rounded,
          color: conflicts.isEmpty ? AppColors.teal : AppColors.coral,
        ),
        title: Text(
          conflicts.isEmpty ? 'No conflicts today' : 'Today’s conflicts',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: conflicts.isEmpty
              ? const Text('None of today’s activities overlap.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final activity in conflicts)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.event_busy_rounded,
                            color: AppColors.coral,
                          ),
                          title: Text(activity.name),
                          subtitle: Text(
                            '${DateFormat.jm().format(activity.startsAt)}–'
                            '${DateFormat.jm().format(activity.endsAt)}',
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _conflicts?.length;
    return Semantics(
      button: true,
      label: 'View conflicting activities',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: _SummaryTile(
          title: 'Conflicts',
          value: _failed ? '—' : (count?.toString() ?? '…'),
          subtitle: _failed
              ? 'tap to retry'
              : count == null
              ? 'syncing schedule'
              : count == 1
              ? 'tap to view conflicting activity'
              : 'tap to view conflicting activities',
          color: AppColors.coral,
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: .035),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: .22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
