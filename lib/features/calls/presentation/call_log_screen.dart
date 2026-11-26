import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app/external_activity_guard.dart';
import '../../../core/presentation/theme/app_spacing.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../../core/widgets/base_screen_shell.dart';
import '../data/phone_contact_source.dart';
import '../domain/call_log_entry.dart';
import '../domain/call_log_repository.dart';
import 'add_call_entry_screen.dart';
import 'edit_call_entry_screen.dart';

class CallLogScreen extends StatefulWidget {
  const CallLogScreen({
    required this.repository,
    required this.contactSource,
    super.key,
  });

  final CallLogRepository repository;
  final PhoneContactSource contactSource;

  @override
  State<CallLogScreen> createState() => _CallLogScreenState();
}

enum _LoadState { loading, ready, permissionDenied, unsupported, error }

enum _CallFilter { all, missed, incoming, outgoing }

class _CallLogScreenState extends State<CallLogScreen>
    with WidgetsBindingObserver {
  _LoadState _state = _LoadState.loading;
  _CallFilter _filter = _CallFilter.all;
  List<CallLogEntry> _entries = const [];
  String? _error;

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
      _load(requestAccess: false);
    }
  }

  Future<void> _load({bool requestAccess = true}) async {
    if (!widget.repository.isSupported) {
      setState(() => _state = _LoadState.unsupported);
      return;
    }
    final granted = requestAccess
        ? await ExternalActivityGuard.run(
            () => widget.repository.requestPermissions(),
          )
        : true;
    if (!mounted) return;
    if (!granted) {
      setState(() => _state = _LoadState.permissionDenied);
      return;
    }
    try {
      final entries = await widget.repository.list();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _state = _LoadState.ready;
      });
    } on CallLogException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _state = _LoadState.error;
      });
    }
  }

  Future<void> _openEdit(CallLogEntry entry) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            EditCallEntryScreen(repository: widget.repository, entry: entry),
      ),
    );
    if (saved == true) {
      await _load(requestAccess: false);
    }
  }

  Future<void> _openAddEntry() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddCallEntryScreen(
          repository: widget.repository,
          contactSource: widget.contactSource,
        ),
      ),
    );
    if (added == true) {
      await _load(requestAccess: false);
    }
  }

  Future<void> _confirmDelete(CallLogEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete call log entry?'),
        content: Text(
          entry.name?.trim().isNotEmpty == true
              ? 'Remove ${entry.name} from the call log?'
              : 'Remove ${entry.number} from the call log?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final deleted = await widget.repository.delete(id: entry.id);
    if (!mounted) return;
    if (deleted) {
      await _load(requestAccess: false);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not delete the call log entry.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreenShell(
      title: 'Call log',
      drawerSelectedIndex: 5,
      floatingActionButton: _state == _LoadState.ready
          ? FloatingActionButton.extended(
              onPressed: _openAddEntry,
              icon: const Icon(Icons.add_call),
              label: const Text('Add call'),
            )
          : null,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case _LoadState.unsupported:
        return _Message(
          icon: Icons.phone_disabled_outlined,
          text: 'The call log is only available on Android.',
        );
      case _LoadState.permissionDenied:
        return _Message(
          icon: Icons.lock_outline,
          text: 'Allow access to the call log to view and add calls.',
          action: FilledButton(
            onPressed: () => _load(),
            child: const Text('Grant access'),
          ),
        );
      case _LoadState.error:
        return _Message(
          icon: Icons.error_outline,
          text: 'Could not read the call log.\n${_error ?? ''}',
          action: FilledButton(
            onPressed: () => _load(requestAccess: false),
            child: const Text('Retry'),
          ),
        );
      case _LoadState.ready:
        if (_entries.isEmpty) {
          return _Message(
            icon: Icons.history,
            text: 'No calls in the call log yet.',
            action: OutlinedButton(
              onPressed: () => _load(requestAccess: false),
              child: const Text('Retry'),
            ),
          );
        }
        final filtered = switch (_filter) {
          _CallFilter.all => _entries,
          _CallFilter.missed =>
            _entries.where((e) => e.type == CallLogType.missed).toList(),
          _CallFilter.incoming =>
            _entries.where((e) => e.type == CallLogType.incoming).toList(),
          _CallFilter.outgoing =>
            _entries.where((e) => e.type == CallLogType.outgoing).toList(),
        };
        final groups = _groupByDate(filtered);
        final timeFormat = DateFormat('h:mm a');
        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  for (final filter in _CallFilter.values) ...[
                    ChoiceChip(
                      label: Text(_filterLabel(filter)),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                    if (filter != _CallFilter.values.last)
                      const SizedBox(width: AppSpacing.xs),
                  ],
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? _Message(
                      icon: Icons.call_outlined,
                      text: 'No ${_filterLabel(_filter).toLowerCase()} calls.',
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(requestAccess: false),
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 96),
                        children: [
                          for (final group in groups) ...[
                            SectionHeader(group.label),
                            SettingsCard(
                              children: [
                                for (final entry in group.entries)
                                  _PixelCallRow(
                                    entry: entry,
                                    timeText: timeFormat.format(
                                      entry.timestamp.toLocal(),
                                    ),
                                    durationText:
                                        entry.type != CallLogType.missed &&
                                            entry.durationSeconds > 0
                                        ? _formatDuration(entry.durationSeconds)
                                        : null,
                                    onTap: () => _openEdit(entry),
                                    onLongPress: () => _confirmDelete(entry),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        );
    }
  }

  static String _filterLabel(_CallFilter filter) => switch (filter) {
    _CallFilter.all => 'All',
    _CallFilter.missed => 'Missed',
    _CallFilter.incoming => 'Incoming',
    _CallFilter.outgoing => 'Outgoing',
  };

  static List<({String label, List<CallLogEntry> entries})> _groupByDate(
    List<CallLogEntry> entries,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateFmt = DateFormat('EEE, d MMM y');

    final map = <String, List<CallLogEntry>>{};
    for (final entry in entries) {
      final local = entry.timestamp.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final label = day == today
          ? 'Today'
          : day == yesterday
          ? 'Yesterday'
          : dateFmt.format(day);
      (map[label] ??= []).add(entry);
    }
    return [for (final e in map.entries) (label: e.key, entries: e.value)];
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }
}

class _PixelCallRow extends StatelessWidget {
  const _PixelCallRow({
    required this.entry,
    required this.timeText,
    required this.durationText,
    required this.onTap,
    required this.onLongPress,
  });

  final CallLogEntry entry;
  final String timeText;
  final String? durationText;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final missed = entry.type == CallLogType.missed;
    final display = entry.name?.trim().isNotEmpty == true
        ? entry.name!.trim()
        : entry.number;
    final initial = entry.name?.trim().isNotEmpty == true
        ? entry.name!.trim()[0].toUpperCase()
        : null;

    final (avatarBg, avatarFg) = missed
        ? (cs.errorContainer, cs.onErrorContainer)
        : (cs.primaryContainer, cs.onPrimaryContainer);

    final typeIcon = switch (entry.type) {
      CallLogType.incoming => Icons.call_received_rounded,
      CallLogType.outgoing => Icons.call_made_rounded,
      CallLogType.missed => Icons.call_missed_rounded,
    };

    final meta = [
      if (entry.name != null && entry.name!.trim().isNotEmpty) entry.number,
      timeText,
      ?durationText,
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      leading: CircleAvatar(
        radius: 21,
        backgroundColor: avatarBg,
        foregroundColor: avatarFg,
        child: initial != null
            ? Text(
                initial,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: avatarFg,
                  fontWeight: FontWeight.w700,
                ),
              )
            : Icon(Icons.person_outline_rounded, color: avatarFg, size: 22),
      ),
      title: Text(
        display,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          color: missed ? cs.error : cs.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Icon(
              typeIcon,
              size: 14,
              color: missed ? cs.error : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: IconButton(
        tooltip: 'Edit call',
        icon: Icon(Icons.edit_outlined, size: 19, color: cs.onSurfaceVariant),
        onPressed: onTap,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
