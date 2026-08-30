import 'package:actibind/core/services/supabase_service.dart';
import 'package:actibind/core/services/home_widget_service.dart';
import 'package:actibind/features/activities/services/activity_service.dart';
import 'package:actibind/features/activities/services/holiday_service.dart';
import 'package:actibind/features/activities/services/usage_stats_service.dart';
import 'package:actibind/features/devices/services/device_app_activity_service.dart';
import 'package:actibind/features/devices/services/registered_device_service.dart';
import 'package:actibind/features/family/services/child_profile_service.dart';
import 'package:actibind/features/notes/services/note_service.dart';
import 'package:actibind/features/routines/services/routine_service.dart';
import 'package:actibind/features/todos/services/todo_service.dart';
import 'package:actibind/features/weather/models/current_weather.dart';
import 'package:actibind/features/weather/services/weather_service.dart';
import 'package:functions_client/functions_client.dart';

class InsightChatMessage {
  const InsightChatMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class InsightService {
  InsightService._();

  static final Map<String, ({String value, DateTime storedAt})> _cache = {};
  static final Map<String, Future<String>> _inFlight = {};

  static Future<String> generateHomeInsight() async {
    final insight = await _request(
      prompt:
          'Give me one concise, practical insight for today in no more than two sentences.',
      mode: 'home',
    );
    await HomeWidgetService.updateInsight(insight);
    return insight;
  }

  static Future<String> generateDailyInsight() async {
    final insight = await _request(
      prompt:
          'Analyze my recent activity and give me a useful daily insight with one specific next action.',
      mode: 'daily',
    );
    await HomeWidgetService.updateInsight(insight);
    return insight;
  }

  static Future<String> generateWeatherTip({
    required CurrentWeather weather,
    required String location,
  }) {
    final cacheKey = [
      'weather',
      location,
      weather.observedAt.toIso8601String(),
      weather.weatherCode,
      weather.temperature.round(),
      weather.windSpeed.round(),
    ].join(':');
    return _cachedRequest(
      cacheKey: cacheKey,
      maxAge: const Duration(minutes: 30),
      request: () => _request(
        prompt:
            'Give one short, practical weather-aware activity planning tip. '
            'Mention a concrete adjustment only when conditions justify it.',
        mode: 'weather',
        includeUsage: false,
        extraContext: {
          'weather': {
            'location': location,
            'temperature_c': weather.temperature,
            'apparent_temperature_c': weather.apparentTemperature,
            'humidity_percent': weather.humidity,
            'wind_kmh': weather.windSpeed,
            'weather_code': weather.weatherCode,
            'is_day': weather.isDay,
            'observed_at': weather.observedAt.toIso8601String(),
          },
        },
      ),
    );
  }

  static Future<String> ask({
    required String question,
    List<InsightChatMessage> history = const [],
  }) => _request(prompt: question, mode: 'chat', history: history);

  static Future<String> _request({
    required String prompt,
    required String mode,
    List<InsightChatMessage> history = const [],
    bool includeUsage = true,
    Map<String, Object?> extraContext = const {},
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) {
      throw const FormatException(
        'Enter a question for the insights assistant.',
      );
    }
    if (cleanPrompt.length > 1000) {
      throw const FormatException(
        'Questions must be 1,000 characters or less.',
      );
    }

    final now = DateTime.now();
    final from = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    final to = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    final activities = await ActivityService.getActivities(from: from, to: to);
    final supportingData = await Future.wait([
      RoutineService.getRoutines(),
      TodoService.getTodos(),
      NoteService.getNotes(),
      RegisteredDeviceService.getDevices(),
      ChildProfileService.getProfiles(),
    ]);
    final routines = supportingData[0] as List<dynamic>;
    final todos = supportingData[1] as List<dynamic>;
    final notes = supportingData[2] as List<dynamic>;
    final devices = supportingData[3] as List<dynamic>;
    final children = supportingData[4] as List<dynamic>;

    CurrentWeather? currentWeather;
    var holidays = const <dynamic>[];
    try {
      currentWeather = await WeatherService.getCurrentWeather(
        latitude: 14.5995,
        longitude: 120.9842,
      );
    } catch (_) {}
    try {
      final holidayLists = await Future.wait(
        {
          from.year,
          to.year,
        }.map((year) => HolidayService.getHolidays(year: year)),
      );
      holidays = holidayLists.expand((items) => items).toList(growable: false);
    } catch (_) {}

    final dates = [
      for (var offset = 0; offset < 7; offset++)
        DateTime(from.year, from.month, from.day + offset),
    ];
    final occurrenceResults = await Future.wait(
      dates.map(RoutineService.getOccurrences),
    );
    final routineOccurrences = <Map<String, Object?>>[];
    for (var index = 0; index < dates.length; index++) {
      for (final occurrence in occurrenceResults[index].values) {
        routineOccurrences.add({
          'routine_id': occurrence.routineId,
          'scheduled_date': occurrence.scheduledDate.toIso8601String(),
          'status': occurrence.status,
        });
      }
    }

    final pcUsage = <Map<String, Object?>>[];
    final pcWindowActivity = <Map<String, Object?>>[];
    for (final device in devices.where((item) => item.isPc == true)) {
      try {
        final results = await Future.wait([
          DeviceAppActivityService.getForDevice(
            deviceId: device.id as String,
            start: from,
            end: now,
          ),
          DeviceAppActivityService.getWindowActivityForDevice(
            deviceId: device.id as String,
            start: from,
            end: now,
          ),
        ]);
        final rows = results[0] as List<dynamic>;
        pcUsage.addAll(
          rows.map(
            (item) => {
              'device_id': device.id,
              'device_name': device.name,
              'app': item.appName,
              'executable': item.packageName,
              'usage_date': item.usageDate.toIso8601String(),
              'foreground_minutes': item.totalSeconds ~/ 60,
              'last_synced_at': item.lastSyncedAt.toIso8601String(),
            },
          ),
        );
        final windows = results[1] as List<Map<String, Object?>>;
        pcWindowActivity.addAll(
          windows.map(
            (item) => {
              'device_id': device.id,
              'device_name': device.name,
              ...item,
            },
          ),
        );
      } catch (_) {
        // Other synchronized sources remain available if one device is stale.
      }
    }

    var usage = const <Map<String, Object>>[];
    if (includeUsage && UsageStatsService.isSupported) {
      try {
        if (await UsageStatsService.hasPermission()) {
          final rows = await UsageStatsService.getUsage(start: from, end: now);
          usage = rows
              .map<Map<String, Object>>(
                (item) => {
                  'app': item.appName,
                  'foreground_minutes': item.foreground.inMinutes,
                  'last_used_at': item.lastTimeUsed.toIso8601String(),
                },
              )
              .toList(growable: false);
        }
      } catch (_) {
        // Schedule-based insights remain available without native usage data.
      }
    }

    late final FunctionResponse response;
    try {
      response = await SupabaseService.client.functions.invoke(
        'groq-insights',
        body: {
          'mode': mode,
          'prompt': cleanPrompt,
          'activities': activities
              .map(
                (item) => {
                  'name': item.name,
                  'category': item.category,
                  'starts_at': item.startsAt.toIso8601String(),
                  'ends_at': item.endsAt.toIso8601String(),
                  'repeat': item.repeat,
                },
              )
              .toList(growable: false),
          'usage': usage,
          'pc_usage': pcUsage,
          'pc_window_activity': pcWindowActivity,
          'devices': devices
              .map(
                (item) => {
                  'id': item.id,
                  'name': item.name,
                  'type': item.type,
                  'platform': item.platform,
                  'connected': item.connected,
                  'last_seen_at': item.lastSeenAt?.toIso8601String(),
                },
              )
              .toList(growable: false),
          'routines': routines
              .map(
                (item) => {
                  'id': item.id,
                  'name': item.name,
                  'category': item.category,
                  'start_minutes': item.startMinutes,
                  'end_minutes': item.endMinutes,
                  'active_days': item.activeDays.toList()..sort(),
                  'active': item.active,
                  'monitor_usage': item.monitorUsage,
                },
              )
              .toList(growable: false),
          'routine_occurrences': routineOccurrences,
          'todos': todos
              .map(
                (item) => {
                  'title': item.title,
                  'priority': item.priority,
                  'completed': item.completed,
                  'due_date': item.dueDate?.toIso8601String(),
                  'completed_at': item.completedAt?.toIso8601String(),
                  'notes': item.notes,
                },
              )
              .toList(growable: false),
          'notes': notes
              .take(30)
              .map(
                (item) => {
                  'title': item.title,
                  'content': item.content,
                  'created_at': item.createdAt.toIso8601String(),
                },
              )
              .toList(growable: false),
          'family_profiles': children
              .map(
                (item) => {
                  'name': item.name,
                  'age_range': item.ageRange,
                  'device': item.device,
                  'connected': item.connected,
                  'restrictions_active': item.restrictionsActive,
                  'screen_time_minutes': item.screenTimeMinutes,
                },
              )
              .toList(growable: false),
          'history': history
              .where(
                (item) =>
                    (item.role == 'user' || item.role == 'assistant') &&
                    item.content.trim().isNotEmpty,
              )
              .take(8)
              .map((item) => item.toJson())
              .toList(growable: false),
          'timezone': now.timeZoneName,
          'local_time': now.toIso8601String(),
          'weather': currentWeather == null
              ? null
              : {
                  'location': 'Manila fallback',
                  'temperature_c': currentWeather.temperature,
                  'apparent_temperature_c': currentWeather.apparentTemperature,
                  'humidity_percent': currentWeather.humidity,
                  'wind_kmh': currentWeather.windSpeed,
                  'weather_code': currentWeather.weatherCode,
                  'is_day': currentWeather.isDay,
                  'observed_at': currentWeather.observedAt.toIso8601String(),
                },
          'holidays': holidays
              .map(
                (item) => {
                  'date': item.date.toIso8601String(),
                  'name': item.name,
                  'national': item.nationalHoliday,
                  'types': item.types,
                },
              )
              .toList(growable: false),
          ...extraContext,
        },
      );
    } on FunctionException catch (error) {
      if (error.status == 429 && error.details is Map) {
        final details = Map<String, dynamic>.from(error.details as Map);
        throw Exception(
          details['error'] as String? ??
              'The daily AI token limit has been reached.',
        );
      }
      rethrow;
    }

    if (response.status != 200 || response.data is! Map) {
      throw Exception('The insights service is temporarily unavailable.');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final insight = data['insight'] as String?;
    if (insight == null || insight.trim().isEmpty) {
      throw Exception('The insights service returned an empty response.');
    }
    return insight.trim();
  }

  static Future<String> _cachedRequest({
    required String cacheKey,
    required Duration maxAge,
    required Future<String> Function() request,
  }) {
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.storedAt) < maxAge) {
      return Future.value(cached.value);
    }
    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;

    final future = request()
        .then((value) {
          _cache[cacheKey] = (value: value, storedAt: DateTime.now());
          return value;
        })
        .whenComplete(() => _inFlight.remove(cacheKey));
    _inFlight[cacheKey] = future;
    return future;
  }
}
