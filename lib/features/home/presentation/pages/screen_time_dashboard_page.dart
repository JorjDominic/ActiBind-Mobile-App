import 'package:actibind/core/constants/app_constants.dart';
import 'package:actibind/core/settings/daily_summary_controller.dart';
import 'package:actibind/core/theme/app_colors.dart';
import 'package:actibind/features/insights/services/insight_service.dart';
import 'package:actibind/features/insights/models/insight_metrics.dart';
import 'package:actibind/features/insights/services/insight_metrics_service.dart';
import 'package:actibind/shared/widgets/app_page_header.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shad;

class ScreenTimeDashboardPage extends StatefulWidget {
  const ScreenTimeDashboardPage({super.key});

  @override
  State<ScreenTimeDashboardPage> createState() =>
      _ScreenTimeDashboardPageState();
}

class _ScreenTimeDashboardPageState extends State<ScreenTimeDashboardPage> {
  String _range = 'Week';
  InsightMetrics? _metrics;
  bool _loadingMetrics = true;
  bool _metricsFailed = false;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    setState(() {
      _loadingMetrics = true;
      _metricsFailed = false;
    });
    try {
      final metrics = await InsightMetricsService.load(
        days: _range == 'Week' ? 7 : 30,
      );
      if (mounted) {
        setState(() {
          _metrics = metrics;
          _loadingMetrics = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _metricsFailed = true;
          _loadingMetrics = false;
        });
      }
    }
  }

  void _changeRange(String value) {
    if (value == _range) return;
    setState(() => _range = value);
    _loadMetrics();
  }

  String get _averageSubtitle {
    final metrics = _metrics;
    final change = metrics?.averageChangePercent;
    if (metrics == null) return 'syncing activity';
    if (change == null) return 'no previous-period baseline yet';
    final direction = change >= 0 ? 'up' : 'down';
    return '${change.abs().round()}% $direction from the previous ${_range.toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppPageHeader(
            title: 'Insights',
            subtitle:
                'Combined phone, PC, schedule, routine, and task patterns',
          ),
          const SizedBox(height: 12),
          _AssistantBanner(onTap: () => _showInsightsChat(context)),
          AnimatedBuilder(
            animation: DailySummaryController.instance,
            builder: (context, _) {
              if (!DailySummaryController.instance.enabled) {
                return const SizedBox(height: 4);
              }
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 12),
                  _AiDailyInsight(),
                  SizedBox(height: 16),
                ],
              );
            },
          ),
          if (_loadingMetrics) const LinearProgressIndicator(),
          if (_metricsFailed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync_problem_rounded),
              title: const Text('Could not sync insight metrics'),
              trailing: TextButton(
                onPressed: _loadMetrics,
                child: const Text('Retry'),
              ),
            ),
          if (_loadingMetrics || _metricsFailed) const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: AppSectionHeader(
                  title: 'At a glance',
                  subtitle: 'Your progress, without the noise',
                ),
              ),
              _InsightsRangeSelector(value: _range, onChanged: _changeRange),
            ],
          ),
          const SizedBox(height: 8),
          _CompactMetrics(
            todayLabel: 'Combined today',
            todayValue: _metrics == null
                ? '—'
                : InsightMetricsService.formatDuration(_metrics!.todayValue),
            averageValue: _metrics == null
                ? '—'
                : InsightMetricsService.formatDuration(_metrics!.dailyAverage),
            averageSubtitle: _averageSubtitle,
            progress: _metrics?.goalProgress ?? 0,
          ),
          const SizedBox(height: 14),
          _DeviceOverview(metrics: _metrics),
          const SizedBox(height: 14),
          const AppSectionHeader(
            title: 'Your activity rhythm',
            subtitle: 'Recorded device use and scheduled activity by day',
          ),
          const SizedBox(height: 8),
          shad.Card(
            filled: true,
            fillColor: AppColors.amber.withValues(alpha: .07),
            borderColor: AppColors.amber.withValues(alpha: .2),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Busiest scheduled window',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _metrics == null
                        ? 'Syncing your activity pattern…'
                        : _metrics!.peakWindow ==
                              'Not enough scheduled activity yet'
                        ? _metrics!.peakWindow
                        : 'Your schedule is busiest around ${_metrics!.peakWindow}.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 96,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        for (var index = 0; index < 7; index++)
                          _DayBar(
                            index: _metrics?.dayLevels[index] ?? .08,
                            label: _weekdayLabels[index],
                            value: _metrics == null
                                ? null
                                : InsightMetricsService.formatDuration(
                                    _metrics!.dayDurations[index],
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  void _showInsightsChat(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: .9,
        child: _InsightsChatSheet(),
      ),
    );
  }
}

class _CompactMetrics extends StatelessWidget {
  const _CompactMetrics({
    required this.todayLabel,
    required this.todayValue,
    required this.averageValue,
    required this.averageSubtitle,
    required this.progress,
  });

  final String todayLabel;
  final String todayValue;
  final String averageValue;
  final String averageSubtitle;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final plannedPercent = (progress * 100).round();
    return shad.Card(
      filled: true,
      fillColor: colors.surface,
      borderColor: AppColors.indigo.withValues(alpha: .18),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.timer_outlined,
                    label: todayLabel,
                    value: todayValue,
                    color: AppColors.indigo,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.trending_up_rounded,
                    label: 'Daily average',
                    value: averageValue,
                    color: AppColors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_available_rounded,
                    size: 20,
                    color: AppColors.amber,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Planned-time share',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              '$plannedPercent%',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.amber,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 7,
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.amber,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                averageSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceOverview extends StatelessWidget {
  const _DeviceOverview({required this.metrics});

  final InsightMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final data = metrics;
    return shad.Card(
      filled: true,
      fillColor: AppColors.indigo.withValues(alpha: .045),
      borderColor: AppColors.indigo.withValues(alpha: .16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Across your devices',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.phone_android_rounded,
                    label: 'Phone today',
                    value: data == null
                        ? '—'
                        : InsightMetricsService.formatDuration(data.phoneToday),
                    color: AppColors.indigo,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.computer_rounded,
                    label: 'PC today',
                    value: data == null
                        ? '—'
                        : InsightMetricsService.formatDuration(data.pcToday),
                    color: AppColors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              data == null
                  ? 'Syncing connected devices…'
                  : '${data.connectedDeviceCount} connected devices · ${data.overLimitAppCount} apps at or above 2 hours',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (data != null && data.topApps.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Top recorded apps',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final app in data.topApps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${app.name} · ${app.source}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        InsightMetricsService.formatDuration(app.duration),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AssistantBanner extends StatelessWidget {
  const _AssistantBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Chat with the ActiBind insights assistant',
    hint: 'Ask questions about activity across your phone, PC, and plans',
    child: Material(
      color: AppColors.indigo,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.forum_rounded, color: Colors.white),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask your Insights Assistant',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Analyze phone, PC, schedules, routines, and tasks',
                      style: TextStyle(color: Color(0xFFE7E7FF), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AiDailyInsight extends StatefulWidget {
  const _AiDailyInsight();

  @override
  State<_AiDailyInsight> createState() => _AiDailyInsightState();
}

class _AiDailyInsightState extends State<_AiDailyInsight> {
  String? _insight;
  bool _loading = true;
  bool _failed = false;
  bool _expanded = false;

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
      _expanded = false;
    });
    try {
      final insight = await InsightService.generateDailyInsight();
      if (mounted) setState(() => _insight = insight);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => shad.Card(
    filled: true,
    fillColor: AppColors.teal.withValues(alpha: .12),
    borderColor: AppColors.teal.withValues(alpha: .32),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: AppColors.teal,
                ),
              ),
              const Expanded(
                child: Text(
                  'Today’s smart takeaway',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.teal,
                  ),
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
          const SizedBox(height: 6),
          if (_loading && _insight == null)
            const LinearProgressIndicator()
          else
            Text(
              _failed && _insight == null
                  ? 'Daily insight is unavailable. Check your connection and try again.'
                  : _insight!,
              maxLines: _expanded ? null : 3,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
          if (_insight != null && _insight!.trim().isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 17,
                ),
                label: Text(_expanded ? 'Show less' : 'See more'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(48, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _InsightsRangeSelector extends StatelessWidget {
  const _InsightsRangeSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'Week', label: Text('Week')),
          ButtonSegment(value: 'Month', label: Text('Month')),
        ],
        selected: {value},
        onSelectionChanged: (value) => onChanged(value.first),
      ),
    );
  }
}

class _InsightsChatSheet extends StatefulWidget {
  const _InsightsChatSheet();

  @override
  State<_InsightsChatSheet> createState() => _InsightsChatSheetState();
}

class _InsightsChatSheetState extends State<_InsightsChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_InsightMessage>[
    const _InsightMessage(
      text:
          'I can analyze your phone and PC usage together with schedules, routines, tasks, and notes. What would you like to explore?',
      isUser: false,
    ),
  ];
  bool _sending = false;

  static const _suggestions = [
    'Which apps use most of my time across devices?',
    'How well does my device use match my schedule?',
    'Summarize my week across phone and PC',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestion]) async {
    final text = (suggestion ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    final history = _messages
        .skip(1)
        .map(
          (message) => InsightChatMessage(
            role: message.isUser ? 'user' : 'assistant',
            content: message.text,
          ),
        )
        .toList(growable: false);
    _controller.clear();
    setState(() {
      _messages.add(_InsightMessage(text: text, isUser: true));
      _sending = true;
    });
    _scrollToBottom();
    try {
      final reply = await InsightService.ask(question: text, history: history);
      if (mounted) {
        setState(
          () => _messages.add(_InsightMessage(text: reply, isUser: false)),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _messages.add(
            const _InsightMessage(
              text:
                  'I could not generate an insight right now. Check your connection and try again.',
              isUser: false,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: AppColors.indigo,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Insights Assistant',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Phone, PC, schedules, routines, and tasks',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) =>
                      _ChatBubble(message: _messages[index]),
                ),
              ),
              if (_sending)
                Semantics(
                  liveRegion: true,
                  label: 'Assistant is preparing a response',
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: LinearProgressIndicator(),
                  ),
                ),
            ],
          ),
        ),
        if (_messages.length == 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in _suggestions)
                  ActionChip(
                    label: Text(suggestion),
                    avatar: const Icon(Icons.arrow_outward_rounded, size: 16),
                    onPressed: _sending ? null : () => _send(suggestion),
                  ),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              10 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Ask about your activity',
                hintText: 'For example, compare my phone and PC activity',
                prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Send message',
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InsightMessage {
  const _InsightMessage({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final _InsightMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: message.isUser
              ? colors.primary
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(17),
            topRight: const Radius.circular(17),
            bottomLeft: Radius.circular(message.isUser ? 17 : 4),
            bottomRight: Radius.circular(message.isUser ? 4 : 17),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? colors.onPrimary : colors.onSurface,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.index, this.label, this.value});

  final double index;
  final String? label;
  final String? value;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: value == null ? 'Syncing' : '${label ?? 'Day'}: $value',
    child: SizedBox(
      width: 30,
      height: 90,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            value ?? '—',
            maxLines: 1,
            overflow: TextOverflow.fade,
            style: const TextStyle(fontSize: 8, color: AppColors.muted),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: 18,
            height: 60 * index,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 3),
          Text(label ?? '', style: const TextStyle(fontSize: 9)),
        ],
      ),
    ),
  );
}
