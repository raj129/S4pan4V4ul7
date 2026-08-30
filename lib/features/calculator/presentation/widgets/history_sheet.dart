import 'package:flutter/material.dart';

import '../../domain/models/history_entry.dart';
import '../theme/calculator_theme.dart';

/// Bottom sheet listing the session's calculations, newest first.
class HistorySheet extends StatelessWidget {
  const HistorySheet({
    required this.entries,
    required this.onEntrySelected,
    required this.onClear,
    super.key,
  });

  final List<HistoryEntry> entries;
  final ValueChanged<HistoryEntry> onEntrySelected;
  final VoidCallback onClear;

  static Future<void> show(
    BuildContext context, {
    required List<HistoryEntry> entries,
    required ValueChanged<HistoryEntry> onEntrySelected,
    required VoidCallback onClear,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: CalculatorTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => HistorySheet(
        entries: entries,
        onEntrySelected: (entry) {
          Navigator.of(sheetContext).pop();
          onEntrySelected(entry);
        },
        onClear: () {
          Navigator.of(sheetContext).pop();
          onClear();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'History',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: CalculatorTheme.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (entries.isNotEmpty)
                  TextButton(
                    onPressed: onClear,
                    child: const Text('Clear'),
                  ),
              ],
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    'No calculations yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: CalculatorTheme.mutedText,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Colors.white12),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                      ),
                      title: Text(
                        entry.expression,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: CalculatorTheme.mutedText,
                        ),
                      ),
                      subtitle: Text(
                        entry.result,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: CalculatorTheme.primaryText,
                        ),
                      ),
                      onTap: () => onEntrySelected(entry),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
