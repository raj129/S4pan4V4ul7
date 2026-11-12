import 'package:flutter/material.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';

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
  bool? isDestructive,
}) async {
  final theme = Theme.of(context);
  final isDeleteAction = isDestructive ??
      (confirmLabel.toLowerCase().contains('delete') ||
          confirmLabel.toLowerCase().contains('empty') ||
          confirmLabel.toLowerCase().contains('remove'));

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        isDeleteAction
            ? Icons.delete_outline_rounded
            : Icons.help_outline_rounded,
        color: isDeleteAction ? theme.colorScheme.error : theme.colorScheme.primary,
        size: 28,
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(content),
      actionsAlignment: MainAxisAlignment.end,
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
          ),
          child: Text(cancelLabel),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          style: isDeleteAction
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                )
              : FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
