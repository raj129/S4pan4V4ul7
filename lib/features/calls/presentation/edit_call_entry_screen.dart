import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/presentation/theme/app_spacing.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../../core/widgets/main_scaffold_scope.dart';
import '../domain/call_log_entry.dart';
import '../domain/call_log_repository.dart';
import 'call_entry_widgets.dart';

/// Edits the time and duration of an existing system call log entry.
/// Pops with `true` once the update has been saved.
class EditCallEntryScreen extends StatefulWidget {
  const EditCallEntryScreen({
    required this.repository,
    required this.entry,
    super.key,
  });

  final CallLogRepository repository;
  final CallLogEntry entry;

  @override
  State<EditCallEntryScreen> createState() => _EditCallEntryScreenState();
}

class _EditCallEntryScreenState extends State<EditCallEntryScreen> {
  late DateTime _when = widget.entry.timestamp;
  late int _durationSeconds = widget.entry.durationSeconds;
  bool _timeManuallyChanged = false;
  bool _saving = false;

  bool get _showsDuration => widget.entry.type != CallLogType.missed;

  Future<void> _pickWhen() async {
    final picked = await pickCallDateTime(context, _when);
    if (picked == null || !mounted) return;
    setState(() {
      _when = picked;
      _timeManuallyChanged = true;
    });
  }

  DateTime _previewTimestamp(DateTime now) => resolveCallLogTimestamp(
    selected: _when,
    durationSeconds: _durationSeconds,
    now: now,
    manuallyChanged: _timeManuallyChanged,
  );

  Future<void> _delete() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete call log entry?'),
        content: const Text('This call will be removed from the call log.'),
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

    setState(() => _saving = true);
    final deleted = await widget.repository.delete(id: widget.entry.id);
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not delete the call log entry.')),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await widget.repository.update(
      id: widget.entry.id,
      timestamp: _previewTimestamp(DateTime.now()),
      durationSeconds: _showsDuration ? _durationSeconds : 0,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not update the call log entry.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entry = widget.entry;
    final preview = _previewTimestamp(DateTime.now());
    final dateText = DateFormat('EEE, d MMM y').format(preview);
    final timeText = DateFormat('h:mm a').format(preview);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit call'),
        actions: [
          IconButton(
            tooltip: 'Delete call',
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const QuickLockActionButton(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          bottom: AppSpacing.xxl,
        ),
        children: [
          SettingsCard(
            children: [
              ListTile(
                leading: SettingsIconBadge(
                  icon: Icons.person_outline_rounded,
                  backgroundColor: cs.primaryContainer,
                  iconColor: cs.onPrimaryContainer,
                ),
                title: Text(entry.name ?? entry.number),
                subtitle: Text(
                  entry.number.isEmpty ? 'Unknown number' : entry.number,
                ),
              ),
            ],
          ),
          if (_showsDuration) ...[
            const SectionHeader('Duration'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: CallDurationField(
                initialSeconds: _durationSeconds,
                onChanged: (seconds) =>
                    setState(() => _durationSeconds = seconds),
              ),
            ),
          ],
          const SectionHeader('Date and time'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: FilledButton.tonalIcon(
              onPressed: _pickWhen,
              icon: const Icon(Icons.schedule_rounded),
              label: Text('$dateText, $timeText'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}
