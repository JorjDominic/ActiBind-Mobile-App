import 'dart:async';

import 'package:actibind/core/theme/app_colors.dart';
import 'package:actibind/features/family/models/family_models.dart';
import 'package:actibind/features/family/services/device_policy_service.dart';
import 'package:actibind/features/family/services/child_mode_session_service.dart';
import 'package:actibind/features/family/services/child_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

class ChildModeSetupPage extends StatefulWidget {
  const ChildModeSetupPage({
    super.key,
    required this.profiles,
    this.policyService,
  });

  final List<ChildProfile> profiles;
  final DevicePolicyService? policyService;

  @override
  State<ChildModeSetupPage> createState() => _ChildModeSetupPageState();
}

class _ChildModeSetupPageState extends State<ChildModeSetupPage> {
  late final DevicePolicyService _policyService =
      widget.policyService ?? AndroidDevicePolicyService.supported;
  int _step = 0;
  String _childId = 'guest';
  int _minutes = 60;
  bool _existingRules = true;
  String? _pin;
  DevicePolicyCapabilities? _capabilities;
  final _allowed = <String>{};
  final _restricted = <String>{};
  bool _restrictEverythingElse = true;
  List<ChildModeApp> _apps = const [];
  bool _loadingApps = true;

  Set<String> get _effectiveRestricted => _restrictEverythingElse
      ? _apps
            .map((app) => app.packageName)
            .where((packageName) => !_allowed.contains(packageName))
            .toSet()
      : _restricted;

  String get _childName => _childId == 'guest'
      ? 'Guest Child'
      : widget.profiles.firstWhere((child) => child.id == _childId).name;

  @override
  void initState() {
    super.initState();
    if (widget.profiles.isNotEmpty) _childId = widget.profiles.first.id;
    _loadCapabilities();
    _loadApps();
  }

  Future<void> _loadApps() async {
    try {
      final apps = await _policyService.installedApps();
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _loadingApps = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingApps = false);
    }
  }

  Future<void> _requestAccessibility() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.accessibility_new_rounded),
        title: const Text('Enable Personal Device Protection'),
        content: const Text(
          'ActiBind uses Android Accessibility only to detect the package name of an app opened during Child Mode. If the parent marked that app restricted, ActiBind returns the child to the protected screen. ActiBind does not read, record, or collect screen content. You can disable this access in Android Settings at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I Understand, Continue'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _policyService.openAccessibilitySettings();
  }

  Future<void> _loadCapabilities() async {
    try {
      final value = await _policyService.capabilities();
      if (mounted) setState(() => _capabilities = value);
    } on PlatformException {
      // The platform implementation is optional on non-Android builds.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Same-Device Child Mode')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              if (_capabilities case final capabilities?)
                _CapabilityBanner(
                  capabilities: capabilities,
                  onEnableAdmin: () async {
                    await _policyService.requestAdmin();
                    await _loadCapabilities();
                  },
                  onEnableAccessibility: _requestAccessibility,
                ),
              Expanded(
                child: Stepper(
                  currentStep: _step,
                  onStepTapped: (value) => setState(() => _step = value),
                  onStepContinue: _continue,
                  onStepCancel: _step == 0
                      ? null
                      : () => setState(() => _step--),
                  controlsBuilder: (context, details) => Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Row(
                      children: [
                        FilledButton(
                          onPressed: details.onStepContinue,
                          child: Text(
                            _step == 3 ? 'Review Child Mode' : 'Continue',
                          ),
                        ),
                        if (_step > 0) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: details.onStepCancel,
                            child: const Text('Back'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  steps: [
                    Step(
                      title: const Text('Select child'),
                      isActive: _step >= 0,
                      content: Column(
                        children: [
                          for (final child in widget.profiles)
                            _ChildChoiceTile(
                              selected: _childId == child.id,
                              title: child.name,
                              subtitle: 'Existing child profile',
                              onTap: () => setState(() => _childId = child.id),
                            ),
                          _ChildChoiceTile(
                            selected: _childId == 'guest',
                            title: 'Temporary Guest Child',
                            subtitle: 'No permanent profile is created',
                            onTap: () => setState(() => _childId = 'guest'),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Duration and rules'),
                      isActive: _step >= 1,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final option in const [30, 60, 120, 180])
                                ChoiceChip(
                                  label: Text(
                                    option == 60
                                        ? '1 hour'
                                        : option == 120
                                        ? '2 hours'
                                        : option == 180
                                        ? 'Custom'
                                        : '30 minutes',
                                  ),
                                  selected: _minutes == option,
                                  onSelected: (_) =>
                                      setState(() => _minutes = option),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              "Use child's existing restrictions",
                            ),
                            subtitle: Text(
                              _existingRules
                                  ? 'Existing profile rules will be loaded'
                                  : 'Create temporary restrictions for this session',
                            ),
                            value: _existingRules,
                            onChanged: (value) =>
                                setState(() => _existingRules = value),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Allowed and restricted apps'),
                      isActive: _step >= 2,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_loadingApps)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_apps.isEmpty)
                            const Text('No launchable applications were found.')
                          else ...[
                            _AppSelector(
                              title: 'Allowed Apps',
                              icon: Icons.check_circle_outline_rounded,
                              color: AppColors.teal,
                              items: _apps,
                              selected: _allowed,
                              excluded: _restricted,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Restrict every other app'),
                              subtitle: const Text(
                                'Recommended: only the apps selected above can be opened.',
                              ),
                              value: _restrictEverythingElse,
                              onChanged: (value) => setState(
                                () => _restrictEverythingElse = value,
                              ),
                            ),
                            if (!_restrictEverythingElse) ...[
                              const SizedBox(height: 12),
                              _AppSelector(
                                title: 'Restricted Apps',
                                icon: Icons.block_rounded,
                                color: AppColors.coral,
                                items: _apps,
                                selected: _restricted,
                                excluded: _allowed,
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Parent PIN'),
                      isActive: _step >= 3,
                      content: _pin == null
                          ? _CreatePin(
                              onSaved: (pin) => setState(() => _pin = pin),
                            )
                          : const ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.verified_user_rounded,
                                color: AppColors.teal,
                              ),
                              title: Text('Parent PIN configured'),
                              subtitle: Text(
                                'The PIN is hidden and required to exit Child Mode.',
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _continue() async {
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    if (_pin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a Parent PIN before continuing.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Child Mode Ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Child: $_childName'),
            Text('Duration: $_minutes minutes'),
            Text('Allowed Apps: ${_allowed.length}'),
            Text('Restricted Apps: ${_effectiveRestricted.length}'),
            const SizedBox(height: 12),
            const Text(
              'Native app blocking will only activate when supported device-management privileges are available.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start Child Mode'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _start();
  }

  Future<void> _start() async {
    final capabilities = await _policyService.capabilities();
    if (!mounted) return;
    setState(() => _capabilities = capabilities);
    final managed = capabilities.isDeviceOwner || capabilities.isProfileOwner;
    if (!managed && !capabilities.isAccessibilityEnabled) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('Protection access required'),
          content: const Text(
            'Enable ActiBind Personal Device Protection in Android Accessibility Settings before starting Child Mode on this phone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    DevicePolicyResult result;
    try {
      result = await _policyService.startChildMode(
        ChildModePolicy(
          childName: _childName,
          duration: Duration(minutes: _minutes),
          allowedApps: _allowed,
          restrictedApps: _effectiveRestricted,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.error_outline_rounded),
          title: const Text('Could not start Child Mode'),
          content: Text(error.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    if (!result.applied) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.info_outline_rounded),
          title: const Text('Preview only'),
          content: Text(result.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continue Preview'),
            ),
          ],
        ),
      );
    }
    if (!mounted) return;
    await ChildModeSessionService.save(
      childId: _childId == 'guest' ? null : _childId,
      childName: _childName,
      minutes: _minutes,
      allowedPackages: _allowed,
      restrictedCount: _effectiveRestricted.length,
      pin: _pin!,
    );
    if (!mounted) return;
    final ended = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => ActiveChildModePage(
          childName: _childName,
          minutes: _minutes,
          allowedCount: _allowed.length,
          restrictedCount: _effectiveRestricted.length,
          allowedApps: _apps
              .where((app) => _allowed.contains(app.packageName))
              .toList(),
          policyService: _policyService,
        ),
      ),
    );
    if (ended == true && mounted) {
      Navigator.pop(context);
    }
  }
}

class _CapabilityBanner extends StatelessWidget {
  const _CapabilityBanner({
    required this.capabilities,
    required this.onEnableAdmin,
    required this.onEnableAccessibility,
  });

  final DevicePolicyCapabilities capabilities;
  final VoidCallback onEnableAdmin;
  final VoidCallback onEnableAccessibility;

  @override
  Widget build(BuildContext context) {
    final managed = capabilities.isDeviceOwner || capabilities.isProfileOwner;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (managed ? AppColors.teal : AppColors.amber).withValues(
          alpha: .1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            managed ? Icons.verified_user_rounded : Icons.info_outline_rounded,
            color: managed ? AppColors.teal : AppColors.amber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              managed
                  ? 'Managed Device Protection available.'
                  : capabilities.isAccessibilityEnabled
                  ? 'Personal Device Protection enabled. Restricted apps will be intercepted.'
                  : 'Enable Personal Device Protection to intercept restricted apps without a factory reset.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (!managed && !capabilities.isAccessibilityEnabled)
            TextButton(
              onPressed: onEnableAccessibility,
              child: const Text('Enable'),
            )
          else if (managed && !capabilities.isAdminActive)
            TextButton(onPressed: onEnableAdmin, child: const Text('Enable')),
        ],
      ),
    );
  }
}

class _ChildChoiceTile extends StatelessWidget {
  const _ChildChoiceTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    color: selected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .55)
        : null,
    child: ListTile(
      onTap: onTap,
      leading: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : AppColors.muted,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.teal)
          : null,
    ),
  );
}

class _AppSelector extends StatefulWidget {
  const _AppSelector({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
    required this.selected,
    required this.excluded,
  });
  final String title;
  final IconData icon;
  final Color color;
  final List<ChildModeApp> items;
  final Set<String> selected;
  final Set<String> excluded;
  @override
  State<_AppSelector> createState() => _AppSelectorState();
}

class _AppSelectorState extends State<_AppSelector> {
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(widget.icon, color: widget.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 360,
            child: ListView.builder(
              itemCount: widget.items.length,
              itemExtent: 64,
              scrollCacheExtent: const ScrollCacheExtent.pixels(256),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: _AppIcon(app: item),
                  title: Text(item.name),
                  subtitle: Text(
                    item.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                  ),
                  value: widget.selected.contains(item.packageName),
                  enabled: !widget.excluded.contains(item.packageName),
                  onChanged: (value) => setState(
                    () => value == true
                        ? widget.selected.add(item.packageName)
                        : widget.selected.remove(item.packageName),
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

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app});
  final ChildModeApp app;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(9),
    child: app.icon == null
        ? Container(
            width: 38,
            height: 38,
            color: AppColors.indigo.withValues(alpha: .1),
            child: const Icon(Icons.apps_rounded, color: AppColors.indigo),
          )
        : Image.memory(
            app.icon!,
            width: 38,
            height: 38,
            cacheWidth: 76,
            cacheHeight: 76,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
          ),
  );
}

class _CreatePin extends StatefulWidget {
  const _CreatePin({required this.onSaved});
  final ValueChanged<String> onSaved;
  @override
  State<_CreatePin> createState() => _CreatePinState();
}

class _CreatePinState extends State<_CreatePin> {
  final first = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  @override
  void dispose() {
    first.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'This PIN is required to exit Child Mode or change protected restriction settings.',
      ),
      const SizedBox(height: 12),
      TextField(
        controller: first,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(
          labelText: 'Parent PIN',
          border: OutlineInputBorder(),
        ),
      ),
      TextField(
        controller: confirm,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: InputDecoration(
          labelText: 'Confirm PIN',
          border: const OutlineInputBorder(),
          errorText: error,
        ),
      ),
      FilledButton(
        onPressed: () {
          final valid =
              RegExp(r'^\d{4,6}$').hasMatch(first.text) &&
              first.text == confirm.text;
          if (!valid) {
            setState(() => error = 'Enter matching 4-6 digit PINs');
            return;
          }
          widget.onSaved(first.text);
        },
        child: const Text('Save PIN'),
      ),
      const SizedBox(height: 6),
      const Text(
        'The PIN is stored as a salted one-way hash and is never displayed after setup.',
        style: TextStyle(fontSize: 11, color: AppColors.muted),
      ),
    ],
  );
}

class ActiveChildModePage extends StatefulWidget {
  const ActiveChildModePage({
    super.key,
    required this.childName,
    required this.minutes,
    required this.allowedCount,
    required this.restrictedCount,
    required this.policyService,
    required this.allowedApps,
    this.onEnded,
  });
  final String childName;
  final int minutes;
  final int allowedCount;
  final int restrictedCount;
  final DevicePolicyService policyService;
  final List<ChildModeApp> allowedApps;
  final VoidCallback? onEnded;
  @override
  State<ActiveChildModePage> createState() => _ActiveChildModePageState();
}

class _ActiveChildModePageState extends State<ActiveChildModePage> {
  int attempts = 0;
  bool _finishing = false;
  Timer? _timer;
  ChildModeSession? _session;
  late final ValueNotifier<int> _remainingSeconds = ValueNotifier(
    widget.minutes * 60,
  );

  @override
  void initState() {
    super.initState();
    _initializeTimer();
  }

  Future<void> _initializeTimer() async {
    final session = await ChildModeSessionService.load();
    if (!mounted) return;
    _session = session;
    _updateRemaining();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateRemaining(),
    );
  }

  void _updateRemaining() {
    final endsAt = _session?.endsAt;
    final seconds =
        endsAt?.difference(DateTime.now()).inSeconds ?? widget.minutes * 60;
    if (!mounted) return;
    _remainingSeconds.value = seconds.clamp(0, 1 << 31);
    if (seconds <= 0) _finishSession();
  }

  String _remainingLabel(int remainingSeconds) {
    final hours = remainingSeconds ~/ 3600;
    final minutes = (remainingSeconds % 3600) ~/ 60;
    final seconds = remainingSeconds % 60;
    return hours > 0
        ? '${hours}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s remaining'
        : '${minutes}m ${seconds.toString().padLeft(2, '0')}s remaining';
  }

  Future<void> _finishSession() async {
    if (_finishing) return;
    _finishing = true;
    _timer?.cancel();
    _timer = null;
    final session = _session;
    if (session != null && session.childId != null) {
      final elapsedSeconds = DateTime.now()
          .difference(session.startedAt)
          .inSeconds;
      final elapsed = (elapsedSeconds / 60).ceil();
      try {
        await ChildProfileService.addScreenTime(session.childId!, elapsed);
      } catch (_) {
        // Ending the protected session must still work while offline.
      }
    }
    final result = await widget.policyService.stopChildMode();
    if (!result.applied) {
      _finishing = false;
      if (mounted) {
        _timer ??= Timer.periodic(
          const Duration(seconds: 1),
          (_) => _updateRemaining(),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
      return;
    }
    await ChildModeSessionService.clear();
    if (!mounted) return;
    if (widget.onEnded case final onEnded?) {
      onEnded();
    } else if (Navigator.of(context).canPop()) {
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _remainingSeconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.lock_clock_rounded,
                      size: 56,
                      color: AppColors.indigo,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Child Mode Active',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (widget.allowedApps.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: GridView.builder(
                          shrinkWrap: true,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: .85,
                              ),
                          itemCount: widget.allowedApps.length,
                          itemBuilder: (context, index) {
                            final app = widget.allowedApps[index];
                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                final opened = await widget.policyService
                                    .launchApp(app.packageName);
                                if (!opened && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Could not open ${app.name}.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _AppIcon(app: app),
                                  const SizedBox(height: 6),
                                  Text(
                                    app.name,
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      widget.childName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    ValueListenableBuilder<int>(
                      valueListenable: _remainingSeconds,
                      builder: (context, seconds, _) => Text(
                        _remainingLabel(seconds),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.allowedCount} Apps Allowed  •  ${widget.restrictedCount} Apps Restricted',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _override,
                      icon: const Icon(Icons.admin_panel_settings_rounded),
                      label: const Text('Parent Override'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _override() async {
    if (attempts >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Too many incorrect attempts. Try again later.'),
        ),
      );
      return;
    }
    final result = await showModalBottomSheet<_OverrideResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ParentOverrideSheet(policyService: widget.policyService),
    );
    if (!mounted || result == null) return;
    if (result == _OverrideResult.unlocked) {
      attempts = 0;
    } else if (result == _OverrideResult.incorrect) {
      setState(() => attempts++);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Incorrect PIN.')));
    } else if (result == _OverrideResult.ended) {
      await _finishSession();
    }
  }
}

enum _OverrideResult { unlocked, incorrect, ended }

class _ParentOverrideSheet extends StatefulWidget {
  const _ParentOverrideSheet({required this.policyService});
  final DevicePolicyService policyService;
  @override
  State<_ParentOverrideSheet> createState() => _ParentOverrideSheetState();
}

class _ParentOverrideSheetState extends State<_ParentOverrideSheet> {
  final input = TextEditingController();
  bool unlocked = false;
  String? error;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    padding: EdgeInsets.fromLTRB(
      20,
      16,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: unlocked ? _controls(context) : _pinEntry(context),
    ),
  );

  Widget _pinEntry(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Enter Parent PIN', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      TextField(
        controller: input,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        onSubmitted: (_) => _unlock(),
        decoration: InputDecoration(
          labelText: 'Parent PIN',
          errorText: error,
          border: const OutlineInputBorder(),
        ),
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
              onPressed: _unlock,
              child: const Text('Unlock'),
            ),
          ),
        ],
      ),
    ],
  );

  Future<void> _unlock() async {
    if (await ChildModeSessionService.verifyPin(input.text)) {
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() => unlocked = true);
    } else {
      if (!mounted) return;
      Navigator.pop(context, _OverrideResult.incorrect);
    }
  }

  Widget _controls(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Parent Controls', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final item in const [
        'Add 30 Minutes',
        'Change Time Limit',
        'Temporarily Allow App',
        'Pause Restrictions',
        'Modify Allowed Apps',
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(item),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.pop(context, _OverrideResult.unlocked),
        ),
      const Divider(),
      ListTile(
        contentPadding: EdgeInsets.zero,
        textColor: AppColors.coral,
        iconColor: AppColors.coral,
        leading: const Icon(Icons.stop_circle_outlined),
        title: const Text('End Child Mode'),
        onTap: () => Navigator.pop(context, _OverrideResult.ended),
      ),
    ],
  );
}
