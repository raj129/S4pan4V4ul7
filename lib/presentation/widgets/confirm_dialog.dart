import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Shows a standard Cancel/Confirm [AlertDialog] and returns `true` only when
/// the user taps the confirm action.
///
/// Centralizes the repeated confirm-dialog pattern used across the gallery,
/// trash, and photo viewer screens to avoid duplicated dialog boilerplate.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'Confirm',
}) async {
  final theme = Theme.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.help_outline_rounded, color: theme.colorScheme.primary),
      title: Text(title),
      content: Text(content),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
