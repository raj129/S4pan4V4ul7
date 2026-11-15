import 'package:flutter/material.dart';

import '../../../calls/data/phone_contact_source.dart';
import '../../application/services/data_sms_service.dart';

/// Returns true for save, false for removal, and null for cancellation.
Future<bool?> showDataSmsNumberDialog(
  BuildContext context, {
  required String? currentNumber,
  required Future<void> Function(String?) saveNumber,
  PhoneContactSource contacts = const PlatformPhoneContactSource(),
}) => showDialog<bool>(
  context: context,
  builder: (_) => _NumberDialog(
    currentNumber: currentNumber,
    saveNumber: saveNumber,
    contacts: contacts,
  ),
);

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.currentNumber,
    required this.saveNumber,
    required this.contacts,
  });

  final String? currentNumber;
  final Future<void> Function(String?) saveNumber;
  final PhoneContactSource contacts;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _controller = TextEditingController(text: widget.currentNumber);
  String? _error;
  bool _saving = false;
  bool _picking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    setState(() => _picking = true);
    try {
      final number = await showDialog<String>(
        context: context,
        builder: (_) => _ContactNumberPicker(source: widget.contacts),
      );
      if (!mounted || number == null) return;
      _controller.text = number;
      setState(() => _error = null);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save({bool remove = false}) async {
    if (_saving || _picking) return;
    String? number;
    try {
      if (!remove) {
        number = DataSmsService.normalizePhone(_controller.text);
        if (number == null) {
          throw const FormatException(
            'Enter a phone number, including + and country code.',
          );
        }
      }
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.saveNumber(remove ? null : number);
      if (mounted) Navigator.of(context).pop(!remove);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not save number: $error';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return PopScope(
      canPop: !_saving && !_picking,
      child: AlertDialog(
        icon: const Icon(Icons.sim_card_outlined),
        title: const Text('Data SMS recipient'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Enter the other person's mobile number, including + and country code. "
                'Saved locally for this conversation only. Both phones need cellular SMS service.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                enabled: !_saving && !_picking,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+919876543210',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  suffixIcon: IconButton(
                    tooltip: 'Choose from contacts',
                    icon: const Icon(Icons.contacts_outlined),
                    onPressed: _saving || _picking ? null : _pickContact,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: _error,
                  errorMaxLines: 4,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving || _picking ? null : _pickContact,
                  icon: const Icon(Icons.contacts_outlined, size: 18),
                  label: const Text('Choose from contacts'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving || _picking
                ? null
                : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (widget.currentNumber != null)
            TextButton(
              onPressed: _saving || _picking ? null : () => _save(remove: true),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Remove'),
            ),
          FilledButton(
            onPressed: _saving || _picking ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _ContactNumberPicker extends StatefulWidget {
  const _ContactNumberPicker({required this.source});

  final PhoneContactSource source;

  @override
  State<_ContactNumberPicker> createState() => _ContactNumberPickerState();
}

class _ContactNumberPickerState extends State<_ContactNumberPicker> {
  List<PhoneContact>? _contacts;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _contacts = null;
      _error = null;
    });
    try {
      final granted = await widget.source.requestPermission();
      if (!mounted) return;
      if (!granted) {
        setState(
          () => _error = 'Contacts access denied. Enter a number manually.',
        );
        return;
      }
      final contacts = await widget.source.read();
      if (mounted) setState(() => _contacts = contacts);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not read contacts: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final digits = query.replaceAll(RegExp(r'[^0-9+]'), '');
    final entries = [
      for (final contact in _contacts ?? const <PhoneContact>[])
        for (final number in contact.numbers)
          if (number.trim().isNotEmpty &&
              (query.isEmpty ||
                  contact.name.toLowerCase().contains(query) ||
                  (digits.isNotEmpty &&
                      number
                          .replaceAll(RegExp(r'[^0-9+]'), '')
                          .contains(digits))))
            (name: contact.name, number: number),
    ];
    return AlertDialog(
      title: const Text('Choose contact number'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Search contacts'),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : _contacts == null
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                  ? const Center(child: Text('No matching phone numbers.'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (_, index) {
                        final entry = entries[index];
                        return ListTile(
                          title: Text(
                            entry.name.isEmpty ? entry.number : entry.name,
                          ),
                          subtitle: Text(entry.number),
                          onTap: () => Navigator.of(context).pop(entry.number),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (_error != null)
          TextButton(onPressed: _load, child: const Text('Retry')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
