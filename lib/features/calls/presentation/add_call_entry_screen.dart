import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/phone_contact_source.dart';
import '../domain/call_log_entry.dart';
import '../domain/call_log_repository.dart';
import 'call_entry_widgets.dart';

/// Pops with `true` once an entry has been written to the call log.
class AddCallEntryScreen extends StatefulWidget {
  const AddCallEntryScreen({
    required this.repository,
    required this.contactSource,
    super.key,
  });

  final CallLogRepository repository;
  final PhoneContactSource contactSource;

  @override
  State<AddCallEntryScreen> createState() => _AddCallEntryScreenState();
}

class _AddCallEntryScreenState extends State<AddCallEntryScreen> {
  List<PhoneContact>? _contacts;
  bool _contactsDenied = false;
  String _query = '';

  PhoneContact? _contact;
  String? _number;
  DateTime _when = DateTime.now();
  CallLogType _type = CallLogType.incoming;
  int _durationSeconds = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final granted = await widget.contactSource.requestPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _contactsDenied = true);
      return;
    }
    final contacts = await widget.contactSource.read();
    if (!mounted) return;
    setState(() => _contacts = contacts);
  }

  List<PhoneContact> get _filtered {
    final all = _contacts ?? const <PhoneContact>[];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    final digits = q.replaceAll(RegExp(r'[^0-9+]'), '');
    return [
      for (final c in all)
        if (c.name.toLowerCase().contains(q) ||
            (digits.isNotEmpty &&
                c.numbers.any(
                  (n) => n.replaceAll(RegExp(r'[^0-9+]'), '').contains(digits),
                )))
          c,
    ];
  }

  Future<void> _pickContact(PhoneContact contact) async {
    String? number;
    if (contact.numbers.length == 1) {
      number = contact.numbers.first;
    } else {
      number = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(contact.name)),
              for (final n in contact.numbers)
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: Text(n),
                  onTap: () => Navigator.of(context).pop(n),
                ),
            ],
          ),
        ),
      );
    }
    if (number == null || !mounted) return;
    setState(() {
      _contact = contact;
      _number = number;
    });
  }

  Future<void> _pickTime() async {
    final picked = await pickCallDateTime(context, _when);
    if (picked == null || !mounted) return;
    setState(() => _when = picked);
  }

  Future<void> _save() async {
    final number = _number;
    if (number == null || _saving) return;
    setState(() => _saving = true);
    final ok = await widget.repository.add(
      number: number,
      name: _contact?.name,
      type: _type,
      timestamp: _when,
      durationSeconds: _type == CallLogType.missed ? 0 : _durationSeconds,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not write to the call log.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_contact == null ? 'Choose contact' : 'New call entry'),
      ),
      body: _contact == null ? _buildContactPicker() : _buildForm(context),
    );
  }

  Widget _buildContactPicker() {
    if (_contactsDenied) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Allow access to contacts to pick a number.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final contacts = _contacts;
    if (contacts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final filtered = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search name or number',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matching contacts.'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final contact = filtered[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          contact.name.isEmpty
                              ? '?'
                              : contact.name[0].toUpperCase(),
                        ),
                      ),
                      title: Text(
                        contact.name.isEmpty
                            ? contact.numbers.first
                            : contact.name,
                      ),
                      subtitle: Text(contact.numbers.join(', ')),
                      onTap: () => _pickContact(contact),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = DateFormat('EEE, d MMM y').format(_when);
    final timeText = DateFormat('h:mm a').format(_when);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(_contact!.name.isEmpty ? _number! : _contact!.name),
          subtitle: Text(_number!),
          trailing: TextButton(
            onPressed: () => setState(() {
              _contact = null;
              _number = null;
            }),
            child: const Text('Change'),
          ),
        ),
        const Divider(),
        const SizedBox(height: 8),
        Text('Call type', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<CallLogType>(
          segments: const [
            ButtonSegment(
              value: CallLogType.incoming,
              label: Text('Incoming'),
              icon: Icon(Icons.call_received),
            ),
            ButtonSegment(
              value: CallLogType.outgoing,
              label: Text('Outgoing'),
              icon: Icon(Icons.call_made),
            ),
            ButtonSegment(
              value: CallLogType.missed,
              label: Text('Missed'),
              icon: Icon(Icons.call_missed),
            ),
          ],
          selected: {_type},
          onSelectionChanged: (selection) =>
              setState(() => _type = selection.first),
        ),
        const SizedBox(height: 24),
        Text('Date and time', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickTime,
          icon: const Icon(Icons.schedule),
          label: Text('$dateText, $timeText'),
        ),
        if (_type != CallLogType.missed) ...[
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
          label: const Text('Save to call log'),
        ),
      ],
    );
  }
}
