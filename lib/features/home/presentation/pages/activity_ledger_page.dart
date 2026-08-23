import 'dart:typed_data';

import 'package:actibind/core/constants/app_constants.dart';
import 'package:actibind/core/theme/app_colors.dart';
import 'package:actibind/features/activities/presentation/widgets/activity_schedule_view.dart';
import 'package:actibind/features/activities/models/app_usage.dart';
import 'package:actibind/features/activities/services/usage_stats_service.dart';
import 'package:actibind/features/devices/models/registered_device.dart';
import 'package:actibind/features/devices/presentation/pages/pc_device_activity_page.dart';
import 'package:actibind/features/devices/services/registered_device_service.dart';
import 'package:actibind/features/todos/presentation/todo_list_view.dart';
import 'package:actibind/shared/widgets/app_page_header.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shad;

class ActivityLedgerPage extends StatefulWidget {
  const ActivityLedgerPage({super.key});

  @override
  State<ActivityLedgerPage> createState() => _ActivityLedgerPageState();
}

class _ActivityLedgerPageState extends State<ActivityLedgerPage> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: AppConstants.defaultPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: 'Activity',
            subtitle: 'Plan your time and review device usage',
            trailing: OutlinedButton.icon(
              onPressed: _openTasks,
              icon: const Icon(Icons.checklist_rounded),
              label: const Text('Tasks'),
            ),
          ),
          const SizedBox(height: 18),
          SegmentedButton<int>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.event_note_rounded),
                label: Text('Planner'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.phone_android_rounded),
                label: Text('Device Activity'),
              ),
            ],
            selected: {_section},
            onSelectionChanged: (value) =>
                setState(() => _section = value.first),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (_section) {
              0 => const ActivityScheduleView(key: ValueKey('schedule')),
              _ => const _DeviceActivityView(key: ValueKey('device')),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openTasks() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: .9,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppConstants.defaultPadding),
        child: TodoListView(),
      ),
    ),
  );
}

class _ScheduleItem {
  const _ScheduleItem({
    required this.name,
    required this.time,
    required this.duration,
    required this.category,
    required this.status,
    required this.icon,
    required this.color,
    this.monitored = true,
  });
  final String name;
  final String time;
  final String duration;
  final String category;
  final String status;
  final IconData icon;
  final Color color;
  final bool monitored;
}

class _ScheduleView extends StatefulWidget {
  const _ScheduleView();
  @override
  State<_ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<_ScheduleView> {
  String _range = 'Today';
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  final _items = <_ScheduleItem>[
    const _ScheduleItem(
      name: 'Study',
      time: '8:00 AM – 10:00 AM',
      duration: '2 hours',
      category: 'Focus Block',
      status: 'Completed',
      icon: Icons.menu_book_rounded,
      color: AppColors.indigo,
    ),
    const _ScheduleItem(
      name: 'Lunch',
      time: '12:00 PM – 1:00 PM',
      duration: '1 hour',
      category: 'Free Time',
      status: 'Completed',
      icon: Icons.restaurant_rounded,
      color: AppColors.teal,
      monitored: false,
    ),
    const _ScheduleItem(
      name: 'Project Work',
      time: '3:00 PM – 5:00 PM',
      duration: '2 hours',
      category: 'Focus Block',
      status: 'Active',
      icon: Icons.work_rounded,
      color: AppColors.amber,
    ),
    const _ScheduleItem(
      name: 'Sleep',
      time: '10:00 PM – 6:00 AM',
      duration: '8 hours',
      category: 'Sleep Block',
      status: 'Upcoming',
      icon: Icons.bedtime_rounded,
      color: AppColors.coral,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isToday
                        ? 'Today'
                        : DateFormat('EEEE').format(_selectedDate),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    DateFormat('MMMM d, y').format(_selectedDate),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _addActivity,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Activity'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ActivityCalendar(
          selectedDate: _selectedDate,
          onSelected: (date) => setState(() {
            _selectedDate = DateUtils.dateOnly(date);
            _range = 'Today';
          }),
          onOpenCalendar: _openCalendar,
        ),
        const SizedBox(height: 16),
        _CurrentActivity(onDetails: () => _showDetails(_items[2])),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'Today', label: Text('Today')),
              ButtonSegment(value: 'Week', label: Text('Week')),
              ButtonSegment(value: 'All', label: Text('All')),
            ],
            selected: {_range},
            onSelectionChanged: (value) => setState(() => _range = value.first),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _range == 'Week' ? 'Weekly schedule' : 'Today’s schedule',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 11),
        if (_range == 'Week')
          const _WeeklySchedule()
        else
          for (final item in _items) ...[
            _ScheduleCard(item: item, onTap: () => _showDetails(item)),
            const SizedBox(height: 11),
          ],
        const SizedBox(height: 10),
        Text('Upcoming', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        const _UpcomingRow(
          day: 'Tomorrow',
          time: '8:00 AM',
          name: 'Study',
          color: AppColors.indigo,
        ),
        const _UpcomingRow(
          day: 'Tomorrow',
          time: '2:00 PM',
          name: 'Project Work',
          color: AppColors.amber,
        ),
        const _UpcomingRow(
          day: 'Monday',
          time: '10:00 PM',
          name: 'Sleep',
          color: AppColors.coral,
        ),
      ],
    );
  }

  Future<void> _openCalendar() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'Select activity date',
    );
    if (date != null && mounted) {
      setState(() {
        _selectedDate = DateUtils.dateOnly(date);
        _range = 'Today';
      });
    }
  }

  Future<void> _addActivity() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ActivityFormSheet(),
    );
    if (created == true && mounted) {
      setState(
        () => _items.add(
          const _ScheduleItem(
            name: 'New Focus Session',
            time: '6:00 PM – 7:00 PM',
            duration: '1 hour',
            category: 'Focus',
            status: 'Upcoming',
            icon: Icons.center_focus_strong_rounded,
            color: AppColors.indigo,
          ),
        ),
      );
    }
  }

  Future<void> _showDetails(_ScheduleItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (_) => _ScheduleDetailSheet(item: item),
    );
    if (!mounted) return;
    if (action == 'edit') {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const _ActivityFormSheet(editing: true),
      );
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this activity?'),
          content: const Text(
            'This activity will be removed from your schedule.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) setState(() => _items.remove(item));
    }
  }
}

class _ActivityCalendar extends StatelessWidget {
  const _ActivityCalendar({
    required this.selectedDate,
    required this.onSelected,
    required this.onOpenCalendar,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final start = selectedDate.subtract(
      Duration(days: selectedDate.weekday - 1),
    );
    final colors = Theme.of(context).colorScheme;

    return shad.Card(
      filled: true,
      fillColor: AppColors.teal.withValues(alpha: .06),
      borderColor: AppColors.teal.withValues(alpha: .2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  size: 19,
                  color: AppColors.teal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    DateFormat('MMMM y').format(selectedDate),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Choose a date',
                  visualDensity: VisualDensity.compact,
                  onPressed: onOpenCalendar,
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                for (var index = 0; index < 7; index++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final date = start.add(Duration(days: index));
                        final selected = DateUtils.isSameDay(
                          date,
                          selectedDate,
                        );
                        final today = DateUtils.isSameDay(date, DateTime.now());
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => onSelected(date),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.teal
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: today && !selected
                                    ? Border.all(color: AppColors.teal)
                                    : null,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    DateFormat(
                                      'E',
                                    ).format(date).substring(0, 1),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? colors.onPrimary
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${date.day}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: selected ? colors.onPrimary : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentActivity extends StatelessWidget {
  const _CurrentActivity({required this.onDetails});
  final VoidCallback onDetails;
  @override
  Widget build(BuildContext context) => shad.Card(
    filled: true,
    fillColor: AppColors.amber.withValues(alpha: .09),
    borderColor: AppColors.amber.withValues(alpha: .25),
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.play_circle_filled_rounded,
                color: AppColors.amber,
                size: 19,
              ),
              SizedBox(width: 7),
              Text(
                'CURRENT ACTIVITY',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Work',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    const Text('3:00 PM – 5:00 PM'),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: onDetails,
                child: const Text('Details'),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const LinearProgressIndicator(
            value: .62,
            minHeight: 7,
            color: AppColors.amber,
            borderRadius: BorderRadius.all(Radius.circular(7)),
          ),
          const SizedBox(height: 7),
          const Text(
            '45 minutes remaining',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.item, required this.onTap});
  final _ScheduleItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => shad.Card(
    borderColor: item.color.withValues(alpha: .22),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: item.color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      _StatusBadge(label: item.status, color: item.color),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.time,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 10,
                    children: [
                      Text(
                        item.duration,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        item.category,
                        style: TextStyle(
                          fontSize: 12,
                          color: item.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.monitored)
                        const Icon(Icons.shield_outlined, size: 15),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700),
    ),
  );
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({
    required this.day,
    required this.time,
    required this.name,
    required this.color,
  });
  final String day;
  final String time;
  final String name;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 11),
        SizedBox(
          width: 75,
          child: Text(day, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(name)),
        Text(
          time,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _WeeklySchedule extends StatelessWidget {
  const _WeeklySchedule();
  @override
  Widget build(BuildContext context) {
    const rows = [
      ('Mon', 'Study · 7 PM', 'Sleep · 10 PM'),
      ('Tue', 'Exercise · 5 PM', 'Study · 7 PM'),
      ('Wed', 'Project · 3 PM', 'Sleep · 10 PM'),
      ('Thu', 'Study · 7 PM', 'Free time · 9 PM'),
      ('Fri', 'Exercise · 5 PM', 'Project · 7 PM'),
    ];
    return shad.Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        row.$1,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(child: Text(row.$2)),
                    Expanded(
                      child: Text(
                        row.$3,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityFormSheet extends StatefulWidget {
  const _ActivityFormSheet({this.editing = false});
  final bool editing;
  @override
  State<_ActivityFormSheet> createState() => _ActivityFormSheetState();
}

class _ActivityFormSheetState extends State<_ActivityFormSheet> {
  String category = 'Focus';
  String repeat = 'Never';
  bool monitor = true;
  bool warnings = true;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      16,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.editing ? 'Edit Activity' : 'Add Activity',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Activity name',
              prefixIcon: Icon(Icons.edit_calendar_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items:
                const [
                      'Study',
                      'Work',
                      'Focus',
                      'Sleep',
                      'Exercise',
                      'Entertainment',
                      'Personal',
                      'Custom',
                    ]
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
            onChanged: (value) => setState(() => category = value ?? category),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(
                child: TextField(
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Start time',
                    hintText: '3:00 PM',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: TextField(
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'End time',
                    hintText: '5:00 PM',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const TextField(
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Date',
              hintText: 'Today',
              prefixIcon: Icon(Icons.calendar_today_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: repeat,
            decoration: const InputDecoration(
              labelText: 'Repeat',
              border: OutlineInputBorder(),
            ),
            items:
                const ['Never', 'Daily', 'Weekdays', 'Weekends', 'Custom Days']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
            onChanged: (value) => setState(() => repeat = value ?? repeat),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: monitor,
            onChanged: (value) => setState(() => monitor = value),
            title: const Text('Monitor device usage'),
            subtitle: const Text('Compare actual usage with this activity'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: warnings,
            onChanged: (value) => setState(() => warnings = value),
            title: const Text('Warn about conflicts'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save Activity'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ScheduleDetailSheet extends StatelessWidget {
  const _ScheduleDetailSheet({required this.item});
  final _ScheduleItem item;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: item.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _DetailRow(label: 'Category', value: item.category),
        _DetailRow(label: 'Date', value: 'Today'),
        _DetailRow(label: 'Time', value: item.time),
        _DetailRow(label: 'Duration', value: item.duration),
        const _DetailRow(label: 'Repeat', value: 'Weekdays'),
        _DetailRow(
          label: 'Monitoring',
          value: item.monitored ? 'Enabled' : 'Off',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'delete'),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'edit'),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Edit'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _DeviceActivityView extends StatefulWidget {
  const _DeviceActivityView({super.key});
  @override
  State<_DeviceActivityView> createState() => _DeviceActivityViewState();
}

class _DeviceActivityViewState extends State<_DeviceActivityView>
    with WidgetsBindingObserver {
  String range = 'Today';
  List<RegisteredDevice> devices = const [];
  bool devicesLoading = true;
  List<AppUsage> usage = const [];
  bool usageLoading = true;
  bool usagePermissionGranted = false;
  String? usageError;
  bool showAllUsage = false;
  bool showAllRecent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDevices();
    _loadUsage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadUsage();
    }
  }

  Future<void> _loadUsage() async {
    if (!UsageStatsService.isSupported) {
      if (mounted) setState(() => usageLoading = false);
      return;
    }
    setState(() {
      usageLoading = true;
      usageError = null;
    });
    try {
      final allowed = await UsageStatsService.hasPermission();
      var rows = const <AppUsage>[];
      if (allowed) {
        final now = DateTime.now();
        final start = range == 'Week'
            ? now.subtract(const Duration(days: 7))
            : DateTime(now.year, now.month, now.day);
        rows = await UsageStatsService.getUsage(start: start, end: now);
      }
      if (mounted) {
        setState(() {
          usagePermissionGranted = allowed;
          usage = rows;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => usageError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => usageLoading = false);
      }
    }
  }

  List<AppUsage> get _recentUsage {
    final recent = [...usage]
      ..sort((a, b) => b.lastTimeUsed.compareTo(a.lastTimeUsed));
    return recent;
  }

  Future<void> _loadDevices() async {
    try {
      final result = await RegisteredDeviceService.getDevices();
      if (mounted) setState(() => devices = result);
    } catch (_) {
      // The sample usage dashboard remains available if sync is unavailable.
    } finally {
      if (mounted) setState(() => devicesLoading = false);
    }
  }

  Future<void> _registerDevice() async {
    final draft = await showModalBottomSheet<_DeviceDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _RegisterDeviceSheet(),
    );
    if (draft == null || !mounted) return;
    try {
      final pairing = await RegisteredDeviceService.createDevice(
        name: draft.name,
        type: draft.type,
        platform: draft.platform,
      );
      await _loadDevices();
      if (mounted) await _showPairingCode(pairing);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not register device: $error')),
        );
      }
    }
  }

  Future<void> _showPairingCode(DevicePairing pairing) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Pair your device'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pairing.device.isPc
                ? 'On ${pairing.device.name}, open the ActiBind PC collector and enter this code. The mobile app remains the controller.'
                : 'On ${pairing.device.name}, open ActiBind, go to Activity > Device Activity, and choose Connect this device.',
          ),
          const SizedBox(height: 18),
          SelectableText(
            '${pairing.code.substring(0, 4)} ${pairing.code.substring(4)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'This one-time code expires in 15 minutes.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  Future<void> _connectThisDevice() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _ConnectDeviceDialog(),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    try {
      final name = await RegisteredDeviceService.connectWithCode(code);
      await _loadDevices();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name is now connected.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect device: $error')),
        );
      }
    }
  }

  Future<void> _removeDevice(RegisteredDevice device) async {
    try {
      if (device.connected) {
        await RegisteredDeviceService.revokeDevice(device.id);
      } else {
        await RegisteredDeviceService.deleteDevicePermanently(device.id);
      }
      await _loadDevices();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove device: $error')),
        );
      }
    }
  }

  Future<void> _deleteDevicePermanently(RegisteredDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete device permanently?'),
        content: Text(
          '${device.name} and all of its synchronized activity history will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await RegisteredDeviceService.deleteDevicePermanently(device.id);
      await _loadDevices();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete device: $error')),
        );
      }
    }
  }

  Future<void> _renewPairingCode(RegisteredDevice device) async {
    try {
      final pairing = await RegisteredDeviceService.renewPairingCode(device);
      await _loadDevices();
      if (mounted) await _showPairingCode(pairing);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create a new code: $error')),
        );
      }
    }
  }

  void _openDevice(RegisteredDevice device) {
    if (device.isPc) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PcDeviceActivityPage(device: device)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Showing activity for ${device.name}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registered devices',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'Personal devices monitored by ActiBind',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: _registerDevice,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add device'),
              ),
              TextButton(
                onPressed: _connectThisDevice,
                child: const Text('Enter pairing code'),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (devicesLoading)
        const LinearProgressIndicator()
      else if (devices.isEmpty)
        _NoDevicesCard(
          onRegister: _registerDevice,
          onConnect: _connectThisDevice,
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            final columns = constraints.maxWidth >= 600 ? 2 : 1;
            final cardWidth =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final device in devices)
                  SizedBox(
                    width: cardWidth,
                    child: _RegisteredDeviceCard(
                      device: device,
                      onTap: () => _openDevice(device),
                      onRemove: () => _removeDevice(device),
                      onRenewPairing: () => _renewPairingCode(device),
                      onDeletePermanently: () =>
                          _deleteDevicePermanently(device),
                    ),
                  ),
              ],
            );
          },
        ),
      const SizedBox(height: 18),
      if (!UsageStatsService.isSupported) ...[
        const _UsageAccessCard(
          message: 'Device activity is available on Android.',
        ),
        const SizedBox(height: 16),
      ] else if (!usagePermissionGranted && !usageLoading) ...[
        _UsageAccessCard(
          message: 'Allow usage access to show your real app activity here.',
          onPressed: UsageStatsService.openPermissionSettings,
        ),
        const SizedBox(height: 16),
      ],
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(range, style: Theme.of(context).textTheme.titleLarge),
                Text(
                  'What you actually did',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'Today', label: Text('Today')),
              ButtonSegment(value: 'Week', label: Text('Week')),
            ],
            selected: {range},
            onSelectionChanged: (value) {
              setState(() {
                range = value.first;
                showAllUsage = false;
                showAllRecent = false;
              });
              _loadUsage();
            },
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (usageLoading)
        const LinearProgressIndicator()
      else if (usageError != null)
        Text('Could not load device activity: $usageError')
      else
        _UsageSummary(usage: usage),
      const SizedBox(height: 22),
      Text('App Usage', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (!usageLoading && usagePermissionGranted && usage.isEmpty)
        const Text('No app usage was recorded for this period.'),
      for (final item in usage.take(showAllUsage ? usage.length : 5))
        _AppUsageRow(
          name: item.appName,
          duration: _formatDuration(item.foreground),
          progress: usage.first.foreground.inMilliseconds == 0
              ? 0
              : item.foreground.inMilliseconds /
                    usage.first.foreground.inMilliseconds,
          icon: Icons.apps_rounded,
          iconBytes: item.iconBytes,
          color: AppColors.indigo,
          onTap: () => _showUsageDetail(context, item),
        ),
      if (usage.length > 5)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => showAllUsage = !showAllUsage),
            icon: Icon(
              showAllUsage
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
            label: Text(
              showAllUsage ? 'See less' : 'See more (${usage.length - 5})',
            ),
          ),
        ),
      const SizedBox(height: 20),
      Text('Recent Activity', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (!usageLoading && usagePermissionGranted && _recentUsage.isEmpty)
        const Text('No recent app activity was recorded.'),
      for (final item in _recentUsage.take(
        showAllRecent ? _recentUsage.length : 3,
      ))
        _HistoryRow(
          time: range == 'Week'
              ? DateFormat('EEE, h:mm a').format(item.lastTimeUsed)
              : DateFormat('h:mm a').format(item.lastTimeUsed),
          app: item.appName,
          duration: _formatDuration(item.foreground),
          icon: Icons.apps_rounded,
          iconBytes: item.iconBytes,
          onTap: () => _showUsageDetail(context, item),
        ),
      if (_recentUsage.length > 3)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => showAllRecent = !showAllRecent),
            icon: Icon(
              showAllRecent
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
            label: Text(
              showAllRecent
                  ? 'See less'
                  : 'See more (${_recentUsage.length - 3})',
            ),
          ),
        ),
      const SizedBox(height: 14),
    ],
  );

  void _showUsageDetail(BuildContext context, AppUsage app) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _AppIcon(iconBytes: app.iconBytes, size: 42, borderRadius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    app.appName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _DetailRow(label: 'App', value: app.appName),
            _DetailRow(label: 'Package', value: app.packageName),
            _DetailRow(
              label: 'Foreground time',
              value: _formatDuration(app.foreground),
            ),
            _DetailRow(
              label: 'Last used',
              value: DateFormat('MMM d, h:mm a').format(app.lastTimeUsed),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
  }
}

class _DeviceDraft {
  const _DeviceDraft({
    required this.name,
    required this.type,
    required this.platform,
  });
  final String name;
  final String type;
  final String platform;
}

class _ConnectDeviceDialog extends StatefulWidget {
  const _ConnectDeviceDialog();

  @override
  State<_ConnectDeviceDialog> createState() => _ConnectDeviceDialogState();
}

class _ConnectDeviceDialogState extends State<_ConnectDeviceDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _connect() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enter pairing code'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.characters,
      maxLength: 9,
      decoration: const InputDecoration(
        labelText: 'Pairing code',
        hintText: 'ABCD 2345',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => _connect(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _connect, child: const Text('Connect')),
    ],
  );
}

class _RegisterDeviceSheet extends StatefulWidget {
  const _RegisterDeviceSheet();
  @override
  State<_RegisterDeviceSheet> createState() => _RegisterDeviceSheetState();
}

class _RegisterDeviceSheetState extends State<_RegisterDeviceSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final String _type = 'mobile';
  String _platform = 'Android';

  List<String> get _platforms => const ['Android', 'iOS', 'Other'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _DeviceDraft(name: _name.text.trim(), type: _type, platform: _platform),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      16,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a device', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 5),
            Text(
              'PC pairing starts in the ActiBind PC Companion. Enter its code from the device list.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Device name',
                hintText: 'My phone',
                prefixIcon: const Icon(Icons.smartphone_rounded),
                border: const OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a device name'
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _platform,
              key: ValueKey(_type),
              decoration: const InputDecoration(
                labelText: 'Platform',
                border: OutlineInputBorder(),
              ),
              items: _platforms
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _platform = value ?? _platform),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('Register Device'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NoDevicesCard extends StatelessWidget {
  const _NoDevicesCard({required this.onRegister, required this.onConnect});
  final VoidCallback onRegister;
  final VoidCallback onConnect;
  @override
  Widget build(BuildContext context) => shad.Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.devices_other_rounded, color: AppColors.indigo),
          const SizedBox(width: 11),
          const Expanded(
            child: Text(
              'Register a PC or mobile device to track its activity.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => value == 'add' ? onRegister() : onConnect(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'add', child: Text('Add a device')),
              PopupMenuItem(
                value: 'connect',
                child: Text('Enter pairing code'),
              ),
            ],
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Add or connect a device',
          ),
        ],
      ),
    ),
  );
}

class _RegisteredDeviceCard extends StatelessWidget {
  const _RegisteredDeviceCard({
    required this.device,
    required this.onTap,
    required this.onRemove,
    required this.onRenewPairing,
    required this.onDeletePermanently,
  });
  final RegisteredDevice device;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onRenewPairing;
  final VoidCallback onDeletePermanently;
  @override
  Widget build(BuildContext context) => shad.Card(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.indigo.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                device.isPc ? Icons.computer_rounded : Icons.smartphone_rounded,
                color: AppColors.indigo,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${device.platform} · ${device.connected
                        ? 'Connected'
                        : device.revokedAt != null
                        ? 'Disconnected'
                        : 'Waiting for pairing'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Device actions',
              onSelected: (value) {
                if (value == 'pair') return onRenewPairing();
                if (value == 'delete') return onDeletePermanently();
                return onRemove();
              },
              itemBuilder: (_) => [
                if (!device.connected && device.revokedAt == null)
                  const PopupMenuItem(
                    value: 'pair',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.password_rounded),
                      title: Text('Show new pairing code'),
                      subtitle: Text('Replaces the previous code'),
                    ),
                  ),
                if (device.connected)
                  const PopupMenuItem(
                    value: 'remove',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.link_off_rounded),
                      title: Text('Disconnect device'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_forever_outlined),
                    title: Text('Delete permanently'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({
    required this.iconBytes,
    required this.size,
    required this.borderRadius,
  });

  final Uint8List? iconBytes;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.indigo.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(borderRadius),
    ),
    child: iconBytes == null
        ? const Icon(Icons.apps_rounded, color: AppColors.indigo)
        : ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Image.memory(
              iconBytes!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.apps_rounded, color: AppColors.indigo),
            ),
          ),
  );
}

class _UsageAccessCard extends StatelessWidget {
  const _UsageAccessCard({required this.message, this.onPressed});
  final String message;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) => shad.Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.query_stats_rounded, color: AppColors.indigo),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          if (onPressed != null)
            FilledButton(
              onPressed: () => onPressed!(),
              child: const Text('Allow access'),
            ),
        ],
      ),
    ),
  );
}

// Kept for the future schedule-conflict integration.
// ignore: unused_element
class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.onDismiss, required this.onView});
  final VoidCallback onDismiss;
  final VoidCallback onView;
  @override
  Widget build(BuildContext context) => shad.Card(
    filled: true,
    fillColor: AppColors.coral.withValues(alpha: .09),
    borderColor: AppColors.coral.withValues(alpha: .28),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.coral),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Schedule Conflict',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.coral,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          const Text(
            'You are currently using TikTok during your Study schedule.',
          ),
          const SizedBox(height: 5),
          const Text(
            'Study · 7:00 PM – 9:00 PM',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 11),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
              TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
              FilledButton.tonal(
                onPressed: onView,
                child: const Text('View Activity'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _UsageSummary extends StatelessWidget {
  const _UsageSummary({required this.usage});
  final List<AppUsage> usage;
  @override
  Widget build(BuildContext context) {
    final total = usage.fold<Duration>(
      Duration.zero,
      (sum, item) => sum + item.foreground,
    );
    final values = <(String, String, IconData, Color, Uint8List?)>[
      (
        _DeviceActivityViewState._formatDuration(total),
        'Screen Time',
        Icons.timer_rounded,
        AppColors.indigo,
        null,
      ),
      (
        usage.isEmpty ? '—' : usage.first.appName,
        'Most Used',
        Icons.apps_rounded,
        AppColors.coral,
        usage.isEmpty ? null : usage.first.iconBytes,
      ),
      (
        '${usage.length}',
        'Apps Used',
        Icons.apps_rounded,
        AppColors.teal,
        null,
      ),
    ];
    return shad.Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 10,
            runSpacing: 15,
            children: [
              for (final value in values)
                SizedBox(
                  width: (constraints.maxWidth - 10) / 2,
                  child: Row(
                    children: [
                      if (value.$5 == null)
                        Icon(value.$3, color: value.$4, size: 20)
                      else
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Image.memory(
                            value.$5!,
                            width: 24,
                            height: 24,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Icon(value.$3, color: value.$4, size: 20),
                          ),
                        ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value.$1,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              value.$2,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _UsageChart extends StatelessWidget {
  const _UsageChart();
  @override
  Widget build(BuildContext context) {
    const bars = [.08, .04, .10, .35, .62, .45, .78, .55, .82, .66, .38, .20];
    return shad.Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Usage throughout the day',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < bars.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(
                          height: 90 * bars[i],
                          decoration: BoxDecoration(
                            color:
                                (i >= 7 && i <= 9
                                        ? AppColors.coral
                                        : AppColors.indigo)
                                    .withValues(alpha: .72),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('12 AM', style: TextStyle(fontSize: 10)),
                Text('6 AM', style: TextStyle(fontSize: 10)),
                Text('12 PM', style: TextStyle(fontSize: 10)),
                Text('6 PM', style: TextStyle(fontSize: 10)),
                Text('12 AM', style: TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AppUsageRow extends StatelessWidget {
  const _AppUsageRow({
    required this.name,
    required this.duration,
    required this.progress,
    required this.icon,
    this.iconBytes,
    required this.color,
    required this.onTap,
  });
  final String name;
  final String duration;
  final double progress;
  final IconData icon;
  final Uint8List? iconBytes;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: iconBytes == null
                ? Icon(icon, color: color, size: 20)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      iconBytes!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Icon(icon, color: color, size: 20),
                    ),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(duration),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress,
                  color: color,
                  backgroundColor: color.withValues(alpha: .1),
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(5),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// Reserved for real schedule-event correlation data.
// ignore: unused_element
class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.schedule,
    required this.time,
    required this.detail,
  });
  final String schedule;
  final String time;
  final String detail;
  @override
  Widget build(BuildContext context) => shad.Card(
    borderColor: AppColors.amber.withValues(alpha: .25),
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.amber),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        schedule,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const _StatusBadge(
                      label: 'Conflict',
                      color: AppColors.amber,
                    ),
                  ],
                ),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.time,
    required this.app,
    required this.duration,
    required this.icon,
    this.iconBytes,
    required this.onTap,
  });
  final String time;
  final String app;
  final String duration;
  final IconData icon;
  final Uint8List? iconBytes;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(
              time,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.indigo.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: iconBytes == null
                ? Icon(icon, size: 17, color: AppColors.indigo)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      iconBytes!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Icon(icon, size: 17, color: AppColors.indigo),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              app,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(duration),
        ],
      ),
    ),
  );
}

// Reserved for persisted intervention-state data.
// ignore: unused_element
class _InterventionLevels extends StatelessWidget {
  const _InterventionLevels();
  @override
  Widget build(BuildContext context) => shad.Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Graduated Intervention',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(
                child: _Level(
                  label: 'Reminder',
                  color: AppColors.teal,
                  active: true,
                ),
              ),
              _LevelLine(),
              Expanded(
                child: _Level(
                  label: 'Warning',
                  color: AppColors.amber,
                  active: true,
                ),
              ),
              _LevelLine(),
              Expanded(
                child: _Level(label: 'Strong', color: AppColors.coral),
              ),
              _LevelLine(),
              Expanded(
                child: _Level(label: 'Restrict', color: AppColors.indigo),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Level extends StatelessWidget {
  const _Level({required this.label, required this.color, this.active = false});
  final String label;
  final Color color;
  final bool active;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: .12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          active ? Icons.check_rounded : Icons.circle_outlined,
          color: active ? Colors.white : color,
          size: 14,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _LevelLine extends StatelessWidget {
  const _LevelLine();
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 2,
      color: Theme.of(context).colorScheme.outlineVariant,
    ),
  );
}
