import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  bool _saving = false;

  bool get _showsDuration => widget.entry.type != CallLogType.missed;

  Future<void> _pickWhen() async {
    final picked = await pickCallDateTime(context, _when);
    if (picked == null || !mounted) return;
    setState(() => _when = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await widget.repository.update(
      id: widget.entry.id,
      timestamp: _when,
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
    final theme = Theme.of(context);
    final entry = widget.entry;
    final dateText = DateFormat('EEE, d MMM y').format(_when);
    final timeText = DateFormat('h:mm a').format(_when);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit call')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(entry.name ?? entry.number),
            subtitle: Text(
              entry.number.isEmpty ? 'Unknown number' : entry.number,
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Text('Date and time', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickWhen,
            icon: const Icon(Icons.schedule),
            label: Text('$dateText, $timeText'),
          ),
          if (_showsDuration) ...[
            const SizedBox(height: 24),
            Text('Duration', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            CallDurationField(
              initialSeconds: _durationSeconds,
              onChanged: (seconds) => _durationSeconds = seconds,
            ),
          ],
          const SizedBox(height: 32),
          FilledButton.icon(
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
        ],
      ),
    );
  }
}
