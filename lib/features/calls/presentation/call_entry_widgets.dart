import 'package:flutter/material.dart';

/// Opens a date picker followed by a time picker. Returns null if cancelled.
Future<DateTime?> pickCallDateTime(
  BuildContext context,
  DateTime initial,
) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime.now().add(const Duration(days: 1)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Minutes and seconds inputs that report the total in seconds.
class CallDurationField extends StatefulWidget {
  const CallDurationField({
    required this.initialSeconds,
    required this.onChanged,
    super.key,
  });

  final int initialSeconds;
  final ValueChanged<int> onChanged;

  @override
  State<CallDurationField> createState() => _CallDurationFieldState();
}

class _CallDurationFieldState extends State<CallDurationField> {
  late final TextEditingController _minutes = TextEditingController(
    text: (widget.initialSeconds ~/ 60).toString(),
  );
  late final TextEditingController _seconds = TextEditingController(
    text: (widget.initialSeconds % 60).toString(),
  );

  @override
  void dispose() {
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _notify() {
    final m = int.tryParse(_minutes.text.trim()) ?? 0;
    final s = (int.tryParse(_seconds.text.trim()) ?? 0).clamp(0, 59).toInt();
    widget.onChanged(m * 60 + s);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _minutes,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Minutes',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _notify(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _seconds,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Seconds',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _notify(),
          ),
        ),
      ],
    );
  }
}
