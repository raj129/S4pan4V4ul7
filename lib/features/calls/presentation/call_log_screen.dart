import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

class _CallLogScreenState extends State<CallLogScreen> {
  _LoadState _state = _LoadState.loading;
  List<CallLogEntry> _entries = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool requestAccess = true}) async {
    if (!widget.repository.isSupported) {
      setState(() => _state = _LoadState.unsupported);
      return;
    }
    final granted = requestAccess
        ? await widget.repository.requestPermissions()
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
    final theme = Theme.of(context);
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
        final timeFormat = DateFormat('d MMM y, h:mm a');
        return RefreshIndicator(
          onRefresh: () => _load(requestAccess: false),
          child: ListView.separated(
            itemCount: _entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = _entries[index];
              final missed = entry.type == CallLogType.missed;
              return ListTile(
                onTap: () => _openEdit(entry),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                leading: Icon(
                  _iconFor(entry.type),
                  color: missed ? theme.colorScheme.error : null,
                ),
                title: Text(
                  entry.name ?? entry.number,
                  style: missed
                      ? TextStyle(color: theme.colorScheme.error)
                      : null,
                ),
                subtitle: Text(
                  [
                    if (entry.name != null) entry.number,
                    timeFormat.format(entry.timestamp),
                    if (!missed && entry.durationSeconds > 0)
                      _formatDuration(entry.durationSeconds),
                  ].join(' · '),
                ),
              );
            },
          ),
        );
    }
  }

  static IconData _iconFor(CallLogType type) => switch (type) {
    CallLogType.incoming => Icons.call_received,
    CallLogType.outgoing => Icons.call_made,
    CallLogType.missed => Icons.call_missed,
  };

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
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
