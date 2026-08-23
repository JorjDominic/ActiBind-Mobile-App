import 'package:actibind/core/theme/app_colors.dart';
import 'package:actibind/features/devices/models/device_app_activity.dart';
import 'package:actibind/features/devices/models/device_app_window_activity.dart';
import 'package:actibind/features/devices/models/registered_device.dart';
import 'package:actibind/features/devices/services/device_app_activity_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PcDeviceActivityPage extends StatefulWidget {
  const PcDeviceActivityPage({super.key, required this.device});
  final RegisteredDevice device;

  @override
  State<PcDeviceActivityPage> createState() => _PcDeviceActivityPageState();
}

class _PcDeviceActivityPageState extends State<PcDeviceActivityPage> {
  String range = 'Today';
  bool loading = true;
  String? error;
  List<DeviceAppActivity> rows = const [];

  DateTime get _end => DateTime.now();
  DateTime get _start =>
      range == 'Week' ? _end.subtract(const Duration(days: 6)) : _end;

  List<_AppSummary> get apps {
    final grouped = <String, _AppSummary>{};
    for (final row in rows) {
      final key = '${row.appName}\u0000${row.packageName}';
      grouped.update(
        key,
        (value) => value.add(row.totalSeconds),
        ifAbsent: () => _AppSummary(
          appName: row.appName,
          packageName: row.packageName,
          totalSeconds: row.totalSeconds,
        ),
      );
    }
    final result = grouped.values.toList()
      ..sort((a, b) => b.totalSeconds.compareTo(a.totalSeconds));
    return result;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await DeviceAppActivityService.getForDevice(
        deviceId: widget.device.id,
        start: _start,
        end: _end,
      );
      if (mounted) setState(() => rows = result);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.device.name),
      actions: [
        IconButton(
          onPressed: loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PC Activity',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      '${widget.device.platform} · ${widget.device.connected ? 'Connected' : 'Disconnected'}',
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
                  setState(() => range = value.first);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.device.lastSeenAt == null
                ? 'This PC has not synchronized yet.'
                : 'Last seen ${DateFormat.yMMMd().add_jm().format(widget.device.lastSeenAt!)}',
          ),
          const SizedBox(height: 18),
          if (loading)
            const LinearProgressIndicator()
          else if (error != null)
            _Message('Could not load PC activity.\n$error')
          else if (apps.isEmpty)
            const _Message('No synchronized PC activity for this period.')
          else ...[
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    _duration(
                      apps.fold(0, (sum, app) => sum + app.totalSeconds),
                    ),
                    'Tracked usage',
                    AppColors.indigo,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(apps.first.appName, 'Most used', AppColors.teal),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Desktop usage',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            for (final app in apps)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.desktop_windows_rounded, size: 19),
                ),
                title: Text(app.appName),
                subtitle: Text(
                  app.packageName.isEmpty
                      ? 'View window details'
                      : '${app.packageName} · View details',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  _duration(app.totalSeconds),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () => _showWindows(app),
              ),
          ],
        ],
      ),
    ),
  );

  Future<void> _showWindows(_AppSummary app) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _WindowSheet(
      app: app,
      future: DeviceAppActivityService.getWindowBreakdown(
        deviceId: widget.device.id,
        start: _start,
        end: _end,
        appName: app.appName,
        packageName: app.packageName,
      ),
    ),
  );

  static String _duration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
  }
}

class _AppSummary {
  const _AppSummary({
    required this.appName,
    required this.packageName,
    required this.totalSeconds,
  });
  final String appName;
  final String packageName;
  final int totalSeconds;
  _AppSummary add(int seconds) => _AppSummary(
    appName: appName,
    packageName: packageName,
    totalSeconds: totalSeconds + seconds,
  );
}

class _WindowSheet extends StatelessWidget {
  const _WindowSheet({required this.app, required this.future});
  final _AppSummary app;
  final Future<List<DeviceAppWindowActivity>> future;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .72,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(app.appName, style: Theme.of(context).textTheme.headlineSmall),
          Text(
            '${_PcDeviceActivityPageState._duration(app.totalSeconds)} total usage',
          ),
          const SizedBox(height: 14),
          Expanded(
            child: FutureBuilder<List<DeviceAppWindowActivity>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _Message('Could not load window activity.');
                }
                final totals = <String, int>{};
                for (final row
                    in snapshot.data ?? const <DeviceAppWindowActivity>[]) {
                  totals[row.windowTitle] =
                      (totals[row.windowTitle] ?? 0) + row.totalSeconds;
                }
                final windows = totals.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                if (windows.isEmpty) {
                  return const _Message(
                    'No window details were recorded for this app.',
                  );
                }
                return ListView.separated(
                  itemCount: windows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tab_rounded),
                    title: Text(
                      windows[index].key,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      _PcDeviceActivityPageState._duration(
                        windows[index].value,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    color: color.withValues(alpha: .08),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}
