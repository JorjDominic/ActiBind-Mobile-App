import 'package:actibind/core/settings/family_mode_controller.dart';
import 'package:actibind/core/services/notification_service.dart';
import 'package:actibind/core/constants/app_constants.dart';
import 'package:actibind/features/home/presentation/pages/activity_ledger_page.dart';
import 'package:actibind/features/family/presentation/pages/family_page.dart';
import 'package:actibind/features/home/presentation/pages/home_overview_page.dart';
import 'package:actibind/features/home/presentation/pages/settings_page.dart';
import 'package:actibind/features/home/presentation/pages/screen_time_dashboard_page.dart';
import 'package:actibind/features/activities/presentation/widgets/activity_schedule_view.dart';
import 'package:actibind/features/activities/services/activity_service.dart';
import 'package:actibind/features/activities/services/activity_validation.dart';
import 'package:actibind/features/activities/models/app_usage.dart';
import 'package:actibind/features/activities/services/app_break_reminder_service.dart';
import 'package:actibind/features/activities/services/usage_stats_service.dart';
import 'package:actibind/features/routines/services/routine_service.dart';
import 'package:actibind/features/routines/presentation/routine_view.dart';
import 'package:actibind/features/insights/services/insight_metrics_service.dart';
import 'package:actibind/features/notifications/models/app_notification.dart';
import 'package:actibind/features/notifications/services/app_notification_service.dart';
import 'package:actibind/shared/widgets/actibind_logo.dart';
import 'package:actibind/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shad;

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.displayName = 'there', this.onSignOut});

  final String displayName;
  final Future<void> Function()? onSignOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  _Destination _selected = _Destination.home;
  final Map<_Destination, Widget> _pages = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.requestPermissionAndSync();
    });
    FamilyModeController.instance.addListener(_handleFamilyModeChange);
    _pages[_Destination.home] = _buildPage(_Destination.home);
  }

  @override
  void dispose() {
    FamilyModeController.instance.removeListener(_handleFamilyModeChange);
    super.dispose();
  }

  void _handleFamilyModeChange() {
    if (!FamilyModeController.instance.enabled &&
        _selected == _Destination.family) {
      _selected = _Destination.home;
      _pages.putIfAbsent(
        _Destination.home,
        () => _buildPage(_Destination.home),
      );
    }
    if (mounted) setState(() {});
  }

  void _onItemTapped(_Destination destination) {
    _pages.putIfAbsent(destination, () => _buildPage(destination));
    setState(() => _selected = destination);
  }

  Widget _buildPage(_Destination destination) => switch (destination) {
    _Destination.home => HomeOverviewPage(
      displayName: widget.displayName,
      onAddActivity: () => _createQuickActivity(name: '', category: 'Focus'),
      onAddRoutine: _createQuickRoutine,
    ),
    _Destination.activity => const ActivityLedgerPage(),
    _Destination.insights => const ScreenTimeDashboardPage(),
    _Destination.family => const FamilyPage(),
    _Destination.settings => SettingsPage(onSignOut: widget.onSignOut),
  };

  Future<void> _createQuickActivity({
    required String name,
    required String category,
  }) async {
    final draft = await showModalBottomSheet<ActivityDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ActivityFormSheet(
        initialDate: DateTime.now(),
        initialName: name,
        initialCategory: category,
      ),
    );
    if (draft == null || !mounted) return;

    try {
      await ActivityService.createActivity(
        name: draft.name,
        category: draft.category,
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
        repeat: draft.repeat,
        monitorUsage: draft.monitorUsage,
        warnConflicts: draft.warnConflicts,
        reminderMinutes: draft.reminderMinutes,
      );
      if (!mounted) return;
      _pages.putIfAbsent(
        _Destination.activity,
        () => _buildPage(_Destination.activity),
      );
      setState(() => _selected = _Destination.activity);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${draft.name} added to your schedule.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create activity: $error')),
      );
    }
  }

  Future<void> _createQuickRoutine() async {
    try {
      final routines = await RoutineService.getRoutines();
      if (!mounted) return;
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => RoutineFormSheet(existing: routines),
      );
      if (saved != true || !mounted) return;
      await NotificationService.syncSchedule();
      _pages.remove(_Destination.activity);
      _pages[_Destination.activity] = _buildPage(_Destination.activity);
      setState(() => _selected = _Destination.activity);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create routine: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return shad.Scaffold(
          headers: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    const ActibindLogo(size: 30, borderRadius: 8),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppConstants.appName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const _NotificationsButton(),
                  ],
                ),
              ),
            ),
            const shad.Divider(),
          ],
          footers: [
            const shad.Divider(),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 10),
              child: AnimatedBuilder(
                animation: FamilyModeController.instance,
                builder: (context, _) => _AppNavigation(
                  selected: _selected,
                  familyModeEnabled: FamilyModeController.instance.enabled,
                  onSelected: _onItemTapped,
                ),
              ),
            ),
          ],
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: IndexedStack(
                index: _Destination.values.indexOf(_selected),
                children: [
                  for (final destination in _Destination.values)
                    TickerMode(
                      enabled: destination == _selected,
                      child: _pages[destination] ?? const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NotificationsButton extends StatelessWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      visualDensity: VisualDensity.compact,
      onPressed: () => _showNotifications(context),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded, size: 24),
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.coral,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => const _NotificationsSheet(),
    );
  }
}

class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet();

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  _NotificationData? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final results = await Future.wait([
        ActivityService.getActivities(
          from: today,
          to: today.add(const Duration(days: 7)),
        ),
        InsightMetricsService.load(days: 7),
        AppNotificationService.getRecent(),
        _loadMobileBreakWarnings(today, now),
      ]);
      final activities = results[0] as List<dynamic>;
      final metrics = results[1] as dynamic;
      final inbox = results[2] as List<AppNotification>;
      final mobileWarnings = results[3] as List<AppUsage>;
      final conflictingIds = <String>{};
      for (var first = 0; first < activities.length; first++) {
        for (var second = first + 1; second < activities.length; second++) {
          final a = activities[first];
          final b = activities[second];
          if (ActivityValidation.intervalsOverlap(
            firstStart: a.startsAt,
            firstEnd: a.endsAt,
            secondStart: b.startsAt,
            secondEnd: b.endsAt,
          )) {
            conflictingIds
              ..add(a.id as String)
              ..add(b.id as String);
          }
        }
      }
      final upcoming = activities
          .where((item) => item.startsAt.isAfter(now))
          .cast<dynamic>()
          .firstOrNull;
      if (mounted) {
        setState(
          () => _data = _NotificationData(
            conflictCount: conflictingIds.length,
            goalPercent: (metrics.goalProgress * 100).round() as int,
            upcomingName: upcoming?.name as String?,
            upcomingTime: upcoming?.startsAt as DateTime?,
            inbox: inbox,
            mobileWarnings: mobileWarnings,
          ),
        );
        await AppNotificationService.markAllRead();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<List<AppUsage>> _loadMobileBreakWarnings(
    DateTime start,
    DateTime end,
  ) async {
    if (!UsageStatsService.isSupported ||
        !await UsageStatsService.hasPermission()) {
      return const [];
    }
    final usage = await UsageStatsService.getUsage(start: start, end: end);
    return AppBreakReminderService.appsOverThreshold(usage);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Refresh notifications',
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (data == null && !_failed) const LinearProgressIndicator(),
          if (_failed)
            ListTile(
              title: const Text('Could not sync notifications'),
              trailing: TextButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ),
          if (data != null) ...[
            for (final warning in data.mobileWarnings) ...[
              _NotificationTile(
                icon: Icons.self_improvement_rounded,
                color: AppColors.coral,
                title: 'Time for a break from ${warning.appName}',
                detail:
                    '${_formatUsage(warning.foreground)} on this phone today. Rest your eyes and stretch.',
                time: 'Screen-time warning',
              ),
              const Divider(height: 1),
            ],
            for (final item in data.inbox) ...[
              _NotificationTile(
                icon: _inboxIcon(item.type),
                color: _inboxColor(item.type),
                title: item.title,
                detail: item.body,
                time: _relativeTime(item.createdAt),
              ),
              const Divider(height: 1),
            ],
            if (data.conflictCount > 0) ...[
              _NotificationTile(
                icon: Icons.warning_amber_rounded,
                color: AppColors.amber,
                title: '${data.conflictCount} conflicting activities',
                detail: 'Open Activity to review the overlapping schedules.',
                time: 'Current schedule',
              ),
              const Divider(height: 1),
            ],
            _NotificationTile(
              icon: Icons.bar_chart_rounded,
              color: AppColors.teal,
              title: 'Focus goal progress',
              detail:
                  'You have completed ${data.goalPercent}% of today’s focus goal.',
              time: 'Synced now',
            ),
            if (data.upcomingName != null) ...[
              const Divider(height: 1),
              _NotificationTile(
                icon: Icons.schedule_rounded,
                color: AppColors.indigo,
                title: '${data.upcomingName} is next',
                detail:
                    'Starts at ${TimeOfDay.fromDateTime(data.upcomingTime!).format(context)}.',
                time: 'Upcoming',
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _formatUsage(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0 ? '$hours hours' : '${hours}h ${minutes}m';
  }

  static IconData _inboxIcon(String type) => switch (type) {
    'break_warning' => Icons.computer_rounded,
    'activity' => Icons.event_rounded,
    'routine' => Icons.repeat_rounded,
    _ => Icons.notifications_rounded,
  };

  static Color _inboxColor(String type) => switch (type) {
    'break_warning' => AppColors.coral,
    'activity' => AppColors.indigo,
    'routine' => AppColors.teal,
    _ => AppColors.amber,
  };

  static String _relativeTime(DateTime createdAt) {
    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.inMinutes < 1) return 'Just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }
}

class _NotificationData {
  const _NotificationData({
    required this.conflictCount,
    required this.goalPercent,
    this.upcomingName,
    this.upcomingTime,
    this.inbox = const [],
    this.mobileWarnings = const [],
  });

  final int conflictCount;
  final int goalPercent;
  final String? upcomingName;
  final DateTime? upcomingTime;
  final List<AppNotification> inbox;
  final List<AppUsage> mobileWarnings;
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.time,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _AppNavigation extends StatelessWidget {
  const _AppNavigation({
    required this.selected,
    required this.familyModeEnabled,
    required this.onSelected,
  });

  final _Destination selected;
  final bool familyModeEnabled;
  final ValueChanged<_Destination> onSelected;

  List<_Destination> get _items => [
    _Destination.home,
    _Destination.activity,
    _Destination.insights,
    if (familyModeEnabled) _Destination.family,
    _Destination.settings,
  ];

  @override
  Widget build(BuildContext context) {
    return shad.NavigationBar(
      key: ValueKey(familyModeEnabled),
      direction: Axis.horizontal,
      expanded: true,
      expandedSize: 48,
      alignment: shad.NavigationBarAlignment.spaceAround,
      labelType: shad.NavigationLabelType.none,
      selectedKey: ValueKey(selected),
      onSelected: (key) => onSelected((key as ValueKey<_Destination>).value),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      children: [
        for (final item in _items)
          shad.NavigationItem(
            key: ValueKey(item),
            label: Text(item.title),
            selectedStyle: const shad.ButtonStyle.ghost(
              density: shad.ButtonDensity.icon,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected == item
                    ? item.color.withValues(alpha: .14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                item.icon,
                size: 24,
                color: selected == item ? item.color : AppColors.muted,
              ),
            ),
          ),
      ],
    );
  }
}

enum _Destination {
  home('Home', Icons.home_rounded, AppColors.indigo),
  activity('Activity', Icons.calendar_month_rounded, AppColors.teal),
  insights('Insights', Icons.bar_chart_rounded, AppColors.amber),
  family('Family', Icons.groups_rounded, AppColors.coral),
  settings('Settings', Icons.settings_rounded, Color(0xFF667085));

  const _Destination(this.title, this.icon, this.color);

  final String title;
  final IconData icon;
  final Color color;
}
