import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:photo_vault/core/presentation/theme/app_colors.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/widgets/app_state_views.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import 'package:photo_vault/features/chat/application/services/chat_backup_service.dart';
import '../../../application/services/onboarding_restore_bridge.dart';
import '../../../domain/entities/user_mode.dart';
import '../../state/onboarding_cubit.dart';
import '../../state/onboarding_state.dart';
import 'onboarding_wizard_header.dart';

/// Post-PIN onboarding step for restoring Chat & Vault from Local or Google Drive.
///
/// - Automatically tries the newly created PIN first.
/// - Prompts for the previous (old) PIN only when the backup was encrypted
///   under a different PIN, then re-wraps both Vault VMK and Chat Identity Key.
/// - Shows live step-by-step progress for chat restoration while vault photo
///   restoration runs in the background.
class OnboardingRestoreScreen extends StatefulWidget {
  const OnboardingRestoreScreen({super.key});

  @override
  State<OnboardingRestoreScreen> createState() =>
      _OnboardingRestoreScreenState();
}

class _OnboardingRestoreScreenState extends State<OnboardingRestoreScreen> {
  OnboardingRestoreSource? _selectedSource;
  String? _selectedVaultId;
  bool _restoreVault = true;
  bool _restoreChat = true;
  bool _restoreVaultPhotos = true;
  bool _restoreSettings = true;
  final _oldPinController = TextEditingController();
  bool _showManualOldPin = false;

  @override
  void dispose() {
    _oldPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<OnboardingCubit, OnboardingState>(
        builder: (context, state) {
          if (state is OnboardingCheckingBackups) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    OnboardingWizardHeader(currentStep: 4),
                    Expanded(
                      child: LoadingView(
                        message:
                            'Checking This device and Google Drive for backups…',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state is OnboardingRestoringBackup) {
            return _RestoringProgressView(
              progress: state.chatProgress,
              restoreChat: state.restoreChat,
            );
          }
          if (state is! OnboardingRestoreAvailable) {
            return const SizedBox.shrink();
          }

          final discovery = state.discovery;
          final effectiveSource =
              _selectedSource ??
              state.selectedSource ??
              (discovery.hasCloudBackup
                  ? OnboardingRestoreSource.googleDrive
                  : OnboardingRestoreSource.local);
          final vaultIds = discovery.vaultIdsFor(effectiveSource);
          final effectiveVaultId =
              (_selectedVaultId != null && vaultIds.contains(_selectedVaultId))
              ? _selectedVaultId
              : (vaultIds.isNotEmpty ? vaultIds.first : null);
          final hasChatForSource =
              effectiveSource == OnboardingRestoreSource.googleDrive
              ? (discovery.hasCloudChat || discovery.hasLocalChat)
              : (discovery.hasLocalChat || discovery.hasCloudChat);
          final canRestoreChat =
              state.mode == UserMode.googleEnabled || hasChatForSource;
          final willRestoreVault = effectiveVaultId != null && _restoreVault;
          final willRestoreChat = canRestoreChat && _restoreChat;
          final showOldPinField = state.needsOldPin || _showManualOldPin;

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                const OnboardingWizardHeader(currentStep: 4),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Restore your chats & vault',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Choose a backup source and what to restore. Vault photos '
                  'restore in the background and show progress in Photos.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (state.errorMessage != null) ...[
                  InfoBanner(
                    message: state.errorMessage!,
                    tone: state.needsOldPin
                        ? InfoBannerTone.warning
                        : InfoBannerTone.error,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (discovery.hasCloudBackup)
                  _SourceCard(
                    title: 'Google Drive',
                    subtitle: _describeSource(
                      hasChat: discovery.hasCloudChat,
                      hasVault: discovery.hasCloudVault,
                    ),
                    icon: Icons.cloud_done_outlined,
                    selected:
                        effectiveSource == OnboardingRestoreSource.googleDrive,
                    onTap: () => setState(() {
                      _selectedSource = OnboardingRestoreSource.googleDrive;
                      _selectedVaultId = null;
                    }),
                  ),
                if (discovery.hasCloudBackup && discovery.hasLocalBackup)
                  const SizedBox(height: AppSpacing.md),
                if (discovery.hasLocalBackup)
                  _SourceCard(
                    title: 'This device (Local)',
                    subtitle: _describeSource(
                      hasChat: discovery.hasLocalChat,
                      hasVault: discovery.hasLocalVault,
                    ),
                    icon: Icons.smartphone_rounded,
                    selected: effectiveSource == OnboardingRestoreSource.local,
                    onTap: () => setState(() {
                      _selectedSource = OnboardingRestoreSource.local;
                      _selectedVaultId = null;
                    }),
                  ),
                if (vaultIds.length > 1) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Select vault backup',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  RadioGroup<String>(
                    groupValue: effectiveVaultId,
                    onChanged: (value) =>
                        setState(() => _selectedVaultId = value),
                    child: Column(
                      children: [
                        for (final id in vaultIds)
                          RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Vault ${_shortId(id)}'),
                            value: id,
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Card.outlined(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      if (canRestoreChat)
                        SwitchListTile(
                          secondary: const Icon(
                            Icons.chat_bubble_outline_rounded,
                          ),
                          title: const Text('Restore chat'),
                          subtitle: Text(
                            _restoreChat
                                ? (hasChatForSource
                                      ? 'Restores chat backup now with live progress.'
                                      : 'Checks & restores chat backup if available.')
                                : 'Skip chat restore and keep history hidden.',
                          ),
                          value: _restoreChat,
                          onChanged: (v) => setState(() => _restoreChat = v),
                        ),
                      if (effectiveVaultId != null) ...[
                        SwitchListTile(
                          secondary: const Icon(Icons.lock_open_rounded),
                          title: const Text('Restore vault'),
                          subtitle: Text(
                            _restoreVault
                                ? 'Restores your encrypted vault key.'
                                : 'Create a new empty vault instead.',
                          ),
                          value: _restoreVault,
                          onChanged: (v) => setState(() => _restoreVault = v),
                        ),
                        SwitchListTile(
                          secondary: const Icon(Icons.photo_library_outlined),
                          title: const Text('Restore vault photos'),
                          subtitle: const Text(
                            'Runs in background; progress visible in Photos.',
                          ),
                          value: _restoreVault && _restoreVaultPhotos,
                          onChanged: _restoreVault
                              ? (v) => setState(() => _restoreVaultPhotos = v)
                              : null,
                        ),
                      ],
                      if (discovery.hasAnySettings)
                        SwitchListTile(
                          secondary: const Icon(Icons.tune_rounded),
                          title: const Text('Restore app settings'),
                          subtitle: const Text(
                            'Theme, security, privacy, and notification preferences.',
                          ),
                          value: _restoreSettings,
                          onChanged: (v) =>
                              setState(() => _restoreSettings = v),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (showOldPinField) ...[
                  TextField(
                    controller: _oldPinController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 4,
                    obscureText: true,
                    autofocus: state.needsOldPin,
                    decoration: const InputDecoration(
                      labelText: 'Previous 4-digit PIN',
                      hintText: 'Enter the PIN used for this backup',
                      counterText: '',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ] else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          setState(() => _showManualOldPin = true),
                      child: const Text('Backup uses an older PIN?'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () {
                    final willRestoreSettings =
                        discovery.hasAnySettings && _restoreSettings;
                    if (!willRestoreVault &&
                        !willRestoreChat &&
                        !willRestoreSettings) {
                      context
                          .read<OnboardingCubit>()
                          .skipRestoreAndCreateVault();
                      return;
                    }
                    final oldPin = showOldPinField
                        ? _oldPinController.text.trim()
                        : null;
                    context.read<OnboardingCubit>().restoreFromSelectedSource(
                      source: effectiveSource,
                      oldPin: (oldPin != null && oldPin.isNotEmpty)
                          ? oldPin
                          : null,
                      selectedVaultId: effectiveVaultId,
                      restoreVault: willRestoreVault,
                      restoreChat: willRestoreChat,
                      restoreVaultPhotos: willRestoreVault && _restoreVaultPhotos,
                      restoreSettings: willRestoreSettings,
                    );
                  },
                  icon: const Icon(Icons.restore_rounded),
                  label: Text(
                    !willRestoreVault &&
                            !willRestoreChat &&
                            !(discovery.hasAnySettings && _restoreSettings)
                        ? 'Continue without restoring'
                        : showOldPinField
                        ? 'Unlock & restore'
                        : 'Restore now',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => context
                      .read<OnboardingCubit>()
                      .skipRestoreAndCreateVault(),
                  child: Text(
                    state.needsOldPin
                        ? 'Forgot old PIN? Start fresh'
                        : 'Skip & start fresh',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _shortId(String id) =>
      id.length <= 8 ? id : '${id.substring(0, 8)}…';

  String _describeSource({required bool hasChat, required bool hasVault}) {
    if (hasChat && hasVault) {
      return 'Chat history & encrypted vault backup available';
    }
    if (hasChat) return 'Chat history backup available';
    if (hasVault) return 'Encrypted vault backup available';
    return 'Backup available';
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;
    return AnimatedContainer(
      duration: AppDuration.fast,
      decoration: BoxDecoration(
        color: selected
            ? tint.withValues(alpha: 0.08)
            : theme.colorScheme.surface,
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(
          color: selected ? tint : theme.colorScheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: Icon(icon, color: selected ? tint : null),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: selected ? tint : theme.colorScheme.outline,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _RestoringProgressView extends StatelessWidget {
  const _RestoringProgressView({
    required this.progress,
    this.restoreChat = true,
  });

  final ChatRestoreProgress? progress;
  final bool restoreChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = progress?.stage ?? ChatRestoreStage.checkingBackups;
    final fraction = progress?.fraction;
    final message = progress?.message ?? 'Preparing restoration…';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OnboardingWizardHeader(currentStep: 4),
            const SizedBox(height: AppSpacing.xl),
            Icon(
              Icons.restore_rounded,
              size: AppSpacing.huge,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Restoring your backups…',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            ClipRRect(
              borderRadius: AppRadius.all(AppRadius.pill),
              child: LinearProgressIndicator(value: fraction, minHeight: 8),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _WorkflowStep(
              label: 'Verify PIN & unlock vault key',
              done: stage.index >= ChatRestoreStage.downloading.index,
              active: stage == ChatRestoreStage.checkingBackups,
            ),
            _WorkflowStep(
              label: restoreChat
                  ? 'Download & decrypt chat backup'
                  : 'Chat restore skipped',
              done:
                  !restoreChat ||
                  stage.index >= ChatRestoreStage.restoringMessages.index,
              active:
                  restoreChat &&
                  (stage == ChatRestoreStage.downloading ||
                      stage == ChatRestoreStage.decrypting),
            ),
            _WorkflowStep(
              label: restoreChat
                  ? 'Restore chat messages & profile'
                  : 'Skip chat history',
              done: !restoreChat || stage == ChatRestoreStage.completed,
              active:
                  restoreChat &&
                  (stage == ChatRestoreStage.restoringMessages ||
                      stage == ChatRestoreStage.restoringProfile),
            ),
            const _WorkflowStep(
              label: 'Restore vault photos in background',
              done: false,
              active: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = done
        ? context.semantic.success
        : active
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : active
                ? Icons.timelapse_rounded
                : Icons.radio_button_unchecked,
            color: color,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style:
                  (active
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
