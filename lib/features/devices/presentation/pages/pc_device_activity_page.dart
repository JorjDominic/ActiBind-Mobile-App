import 'package:actibind/core/theme/app_colors.dart';
import 'package:actibind/features/devices/models/device_app_activity.dart';
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
      final end = DateTime.now();
      final start = range == 'Week'
          ? end.subtract(const Duration(days: 6))
          : end;
      final result = await DeviceAppActivityService.getForDevice(
        deviceId: widget.device.id,
        start: start,
        end: end,
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
          else if (rows.isEmpty)
            const _Message('No synchronized PC activity for this period.')
          else ...[
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    _duration(
                      rows.fold(0, (sum, row) => sum + row.totalSeconds),
                    ),
                    'Tracked usage',
                    AppColors.indigo,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(rows.first.appName, 'Most used', AppColors.teal),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Desktop usage',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final row in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.desktop_windows_rounded, size: 19),
                ),
                title: Text(row.appName),
                subtitle: row.packageName.isEmpty
                    ? null
                    : Text(row.packageName, maxLines: 1),
                trailing: Text(
                  _duration(row.totalSeconds),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ],
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
