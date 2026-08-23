import 'package:actibind/core/theme/app_colors.dart';
import 'package:actibind/features/devices/models/device_app_activity.dart';
import 'package:actibind/features/devices/models/device_app_window_activity.dart';
import 'package:actibind/features/devices/models/registered_device.dart';
import 'package:actibind/features/devices/services/device_app_activity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
                      widget.device.platform,
                      style: TextStyle(
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
                  setState(() => range = value.first);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            color: (widget.device.connected ? AppColors.teal : AppColors.coral)
                .withValues(alpha: .08),
            child: ListTile(
              leading: Icon(
                widget.device.connected
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                color: widget.device.connected
                    ? AppColors.teal
                    : AppColors.coral,
              ),
              title: Text(
                widget.device.connected
                    ? 'Connected and syncing'
                    : 'Disconnected',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                widget.device.lastSeenAt == null
                    ? 'No activity has been synchronized yet.'
                    : 'Last seen ${DateFormat.yMMMd().add_jm().format(widget.device.lastSeenAt!)}',
              ),
            ),
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
            const SizedBox(height: 10),
            _Stat('${apps.length}', 'Apps used', AppColors.amber),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'App usage',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  range,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final app in apps)
              _AppUsageCard(
                app: app,
                maximumSeconds: apps.first.totalSeconds,
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

class _AppUsageCard extends StatelessWidget {
  const _AppUsageCard({
    required this.app,
    required this.maximumSeconds,
    required this.onTap,
  });
  final _AppSummary app;
  final int maximumSeconds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _appColor(app);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _OnlineAppIcon(app: app, color: color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            app.appName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          _PcDeviceActivityPageState._duration(
                            app.totalSeconds,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      app.packageName.isEmpty
                          ? 'View window details'
                          : '${app.packageName} · View details',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value: maximumSeconds == 0
                            ? 0
                            : app.totalSeconds / maximumSeconds,
                        color: color,
                        backgroundColor: color.withValues(alpha: .12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  static String _identity(_AppSummary app) =>
      '${app.appName} ${app.packageName}'.toLowerCase();

  static Color _appColor(_AppSummary app) {
    final id = _identity(app);
    if (id.contains('chrome')) return const Color(0xFF4285F4);
    if (id.contains('spotify')) return const Color(0xFF1DB954);
    if (id.contains('code')) return const Color(0xFF007ACC);
    if (id.contains('discord')) return const Color(0xFF5865F2);
    if (id.contains('firefox')) return const Color(0xFFFF7139);
    return AppColors.indigo;
  }
}

class _OnlineAppIcon extends StatelessWidget {
  const _OnlineAppIcon({required this.app, required this.color});
  final _AppSummary app;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final id = _AppUsageCard._identity(app);
    if (_isActiBindCompanion(id)) {
      return Padding(
        padding: const EdgeInsets.all(5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.asset(
            'assets/icons/ActiBind Logo Dark Version.png',
            width: 34,
            height: 34,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
      );
    }

    final iconPath = _iconPath(app);
    final fallback = _InitialIcon(app: app, color: color);
    if (iconPath == null) return fallback;
    return Padding(
      padding: const EdgeInsets.all(9),
      child: SvgPicture.network(
        'https://api.iconify.design/$iconPath.svg',
        width: 26,
        height: 26,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => fallback,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  static String? _iconPath(_AppSummary app) {
    final id = _AppUsageCard._identity(app);
    if (id.contains('chrome')) return 'logos/chrome';
    if (id.contains('edge')) return 'logos/microsoft-edge';
    if (id.contains('firefox')) return 'logos/firefox';
    if (id.contains('brave')) return 'logos/brave';
    if (id.contains('opera')) return 'logos/opera';
    if (id.contains('code') || id.contains('devenv')) {
      return 'logos/visual-studio-code';
    }
    if (id.contains('android studio')) return 'logos/android-icon';
    if (id.contains('intellij')) return 'logos/intellij-idea';
    if (id.contains('pycharm')) return 'logos/pycharm';
    if (id.contains('postman')) return 'logos/postman-icon';
    if (id.contains('powershell')) return 'vscode-icons/file-type-powershell';
    if (id.contains('python')) return 'logos/python';
    if (id.contains('github')) return 'logos/github-icon';
    if (id.contains('spotify')) return 'logos/spotify-icon';
    if (id.contains('discord')) return 'logos/discord-icon';
    if (id.contains('slack')) return 'logos/slack-icon';
    if (id.contains('teams')) return 'logos/microsoft-teams';
    if (id.contains('zoom')) return 'logos/zoom-icon';
    if (id.contains('skype')) return 'logos/skype';
    if (id.contains('telegram')) return 'logos/telegram';
    if (id.contains('whatsapp')) return 'logos/whatsapp-icon';
    if (id.contains('signal')) return 'logos/signal';
    if (id.contains('word')) return 'vscode-icons/file-type-word';
    if (id.contains('excel')) return 'vscode-icons/file-type-excel';
    if (id.contains('powerpoint')) return 'vscode-icons/file-type-powerpoint';
    if (id.contains('outlook')) return 'logos/microsoft-icon';
    if (id.contains('onedrive')) return 'logos/microsoft-onedrive';
    if (id.contains('notion')) return 'logos/notion-icon';
    if (id.contains('obsidian')) return 'logos/obsidian-icon';
    if (id.contains('figma')) return 'logos/figma';
    if (id.contains('canva')) return 'thesvg-color/canva';
    if (id.contains('blender')) return 'logos/blender';
    if (id.contains('photoshop')) return 'logos/adobe-photoshop';
    if (id.contains('illustrator')) return 'logos/adobe-illustrator';
    if (id.contains('acrobat')) return 'selfhst/adobe-acrobat';
    if (id.contains('dropbox')) return 'logos/dropbox';
    if (id.contains('google drive')) return 'logos/google-drive';
    if (id.contains('steam')) return 'logos/steam';
    if (id.contains('epic')) return 'streamline-color/epic-games-1';
    if (id.contains('unity')) return 'logos/unity';
    if (id.contains('unreal')) return 'logos/unrealengine-icon';
    if (id.contains('roblox')) return 'material-icon-theme/roblox';
    if (id.contains('twitch')) return 'logos/twitch';
    if (id.contains('youtube')) return 'logos/youtube-icon';
    if (id.contains('vlc')) return 'flat-color-icons/vlc';
    if (id.contains('netflix')) return 'logos/netflix-icon';
    if (id.contains('facebook')) return 'logos/facebook';
    if (id.contains('instagram')) return 'skill-icons/instagram';
    if (id.contains('tiktok')) return 'logos/tiktok-icon';
    if (id.contains('reddit')) return 'logos/reddit-icon';
    if (id.contains('linkedin')) return 'logos/linkedin-icon';
    if (id.contains('x.com') || id.contains('twitter')) return 'logos/twitter';
    if (id.contains('gmail')) return 'logos/google-gmail';
    if (id.contains('calendar')) return 'logos/google-calendar';
    if (id.contains('microsoft store')) return 'logos/microsoft-icon';
    if (id.contains('windows terminal') || id.contains('windowsterminal')) {
      return 'logos/microsoft-windows-icon';
    }
    if (id.contains('7-zip') || id.contains('7zip')) {
      return 'vscode-icons/file-type-zip';
    }
    return null;
  }

  static bool _isActiBindCompanion(String id) =>
      id.contains('actibind') &&
      (id.contains('companion') ||
          id.contains('collector') ||
          id.contains('pc'));
}

class _InitialIcon extends StatelessWidget {
  const _InitialIcon({required this.app, required this.color});

  final _AppSummary app;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final name = app.appName.trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
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
