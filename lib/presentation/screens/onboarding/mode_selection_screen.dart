import 'package:flutter/material.dart';

import '../../../application/usecases/select_mode_usecase.dart';
import '../../../domain/entities/user_mode.dart';
import '../../theme/app_spacing.dart';

class ModeSelectionScreen extends StatefulWidget {
  const ModeSelectionScreen({required this.selectModeUseCase, super.key});

  final SelectModeUseCase selectModeUseCase;

  @override
  State<ModeSelectionScreen> createState() => _ModeSelectionScreenState();
}

class _ModeSelectionScreenState extends State<ModeSelectionScreen> {
  bool _isSaving = false;
  UserMode? _selectedMode;

  Future<void> _pickMode(UserMode mode) async {
    setState(() {
      _selectedMode = mode;
      _isSaving = true;
    });

    await widget.selectModeUseCase.execute(mode);

    if (!mounted) return;

    setState(() => _isSaving = false);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Photo Vault')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Icon(
                      Icons.enhanced_encryption_rounded,
                      size: AppSpacing.huge,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Choose how your vault starts',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'You can enable Google backup later from settings.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    ...UserMode.values.map(
                      (mode) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _ModeCard(
                          mode: mode,
                          selected: _selectedMode == mode,
                          enabled: !_isSaving,
                          onTap: () => _pickMode(mode),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: AppDuration.fast,
                child: _isSaving
                    ? const ClipRRect(
                        borderRadius: BorderRadius.all(
                          Radius.circular(AppRadius.pill),
                        ),
                        child: LinearProgressIndicator(),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final UserMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;

    return AnimatedContainer(
      duration: AppDuration.fast,
      decoration: BoxDecoration(
        color: selected
            ? tint.withValues(alpha: 0.10)
            : theme.colorScheme.surface,
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(
          color: selected ? tint : theme.colorScheme.outlineVariant,
        ),
      ),
      child: ListTile(
        enabled: enabled,
        leading: Icon(_iconFor(mode), color: selected ? tint : null),
        title: Text(mode.title),
        subtitle: Text(mode.description),
        trailing: AnimatedSwitcher(
          duration: AppDuration.fast,
          child: selected
              ? Icon(
                  Icons.check_circle_rounded,
                  key: const ValueKey('selected'),
                  color: tint,
                )
              : const Icon(
                  Icons.arrow_forward_ios_rounded,
                  key: ValueKey('idle'),
                ),
        ),
        onTap: enabled ? onTap : null,
      ),
    );
  }

  IconData _iconFor(UserMode mode) {
    return switch (mode) {
      UserMode.localOnly => Icons.smartphone_rounded,
      UserMode.googleEnabled => Icons.cloud_done_outlined,
      UserMode.hybrid => Icons.sync_lock_rounded,
    };
  }
}
