import 'package:flutter/material.dart';

import '../../../application/services/restore_flow_service.dart';
import '../../../core/widgets/app_state_views.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class RestoreFlowScreen extends StatefulWidget {
  const RestoreFlowScreen({
    required this.authRepository,
    required this.restoreFlowService,
    required this.onRestoreCompleted,
    super.key,
  });

  final AuthRepository authRepository;
  final RestoreFlowService restoreFlowService;
  final Future<void> Function(String pin, bool includePhotos)
  onRestoreCompleted;

  @override
  State<RestoreFlowScreen> createState() => _RestoreFlowScreenState();
}

class _RestoreFlowScreenState extends State<RestoreFlowScreen> {
  bool _loading = true;
  bool _signedIn = false;
  bool _manifestAvailable = false;
  bool _manifestFetched = false;
  bool _vmkRestored = false;
  bool _includePhotos = true;
  bool _submitting = false;
  String _pin = '';
  String _confirmPin = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final signedIn = await widget.authRepository.isSignedIn();
    final available = signedIn
        ? await widget.restoreFlowService.hasBackupManifest()
        : false;
    if (!mounted) return;
    setState(() {
      _signedIn = signedIn;
      _manifestAvailable = available;
      _loading = false;
    });
  }

  Future<void> _signIn() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authRepository.signInWithGoogle();
      final available = await widget.restoreFlowService.hasBackupManifest();
      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _manifestAvailable = available;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Google sign-in failed.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _fetchManifest() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.restoreFlowService.fetchBackupManifest();
      if (!mounted) return;
      setState(() => _manifestFetched = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Failed to fetch backup manifest.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _restoreVmk() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.restoreFlowService.restoreEncryptedVmk();
      if (!mounted) return;
      setState(() => _vmkRestored = true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _vmkRestored = true;
        _error =
            'No backup VMK found. A new encryption key will be created when you enter your PIN below.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _completeRestore() async {
    if (_pin.length != 4 || _pin != _confirmPin) {
      setState(() => _error = 'Enter matching 4-digit PIN values.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.restoreFlowService.restoreMetadataAndPhotos(
        includePhotos: _includePhotos,
      );
      await widget.onRestoreCompleted(_pin, _includePhotos);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Restore failed. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: LoadingView(message: 'Checking backups…'));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Restore Vault')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'Restore from encrypted backup',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Sign in, fetch the manifest, restore the wrapped key, then create a local PIN.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsCard(
            margin: EdgeInsets.zero,
            dividers: false,
            children: [
              _RestoreStepRow(
                index: 1,
                title: 'Sign in with Google',
                state: _signedIn ? _StepState.done : _StepState.active,
                actionLabel: _signedIn ? null : 'Sign in',
                onAction: _signedIn || _submitting ? null : _signIn,
              ),
              _RestoreStepRow(
                index: 2,
                title: 'Fetch backup manifest',
                subtitle: !_signedIn
                    ? 'Sign in first.'
                    : (!_manifestAvailable
                          ? 'No backup manifest found for this account.'
                          : 'Download the encrypted backup index.'),
                state: _manifestFetched
                    ? _StepState.done
                    : (_signedIn ? _StepState.active : _StepState.pending),
                actionLabel:
                    _signedIn && _manifestAvailable && !_manifestFetched
                    ? 'Fetch'
                    : null,
                onAction:
                    (_signedIn &&
                        _manifestAvailable &&
                        !_manifestFetched &&
                        !_submitting)
                    ? _fetchManifest
                    : null,
              ),
              _RestoreStepRow(
                index: 3,
                title: 'Restore encrypted VMK backup',
                subtitle: 'Recover or recreate the key envelope locally.',
                state: _vmkRestored
                    ? _StepState.done
                    : (_manifestFetched
                          ? _StepState.active
                          : _StepState.pending),
                actionLabel: _manifestFetched && !_vmkRestored
                    ? 'Restore VMK'
                    : null,
                onAction: (_manifestFetched && !_vmkRestored && !_submitting)
                    ? _restoreVmk
                    : null,
              ),
              _RestoreStepRow(
                index: 4,
                title: 'Create new local PIN',
                subtitle: 'Re-wrap the restored key for this device.',
                state: _vmkRestored ? _StepState.active : _StepState.pending,
                isLast: true,
                child: _PinStepContent(
                  enabled: _vmkRestored && !_submitting,
                  includePhotos: _includePhotos,
                  submitting: _submitting,
                  onPinChanged: (v) => _pin = v,
                  onConfirmPinChanged: (v) => _confirmPin = v,
                  onIncludePhotosChanged: (v) =>
                      setState(() => _includePhotos = v ?? true),
                  onComplete: _completeRestore,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            InfoBanner(message: _error!, tone: InfoBannerTone.error),
          ],
        ],
      ),
    );
  }
}

enum _StepState { pending, active, done }

class _RestoreStepRow extends StatelessWidget {
  const _RestoreStepRow({
    required this.index,
    required this.title,
    required this.state,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.child,
    this.isLast = false,
  });

  final int index;
  final String title;
  final String? subtitle;
  final _StepState state;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? child;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = context.semantic.success;
    final active = theme.colorScheme.primary;
    final pending = theme.colorScheme.outline;
    final color = switch (state) {
      _StepState.done => success,
      _StepState.active => active,
      _StepState.pending => pending,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                AnimatedContainer(
                  duration: AppDuration.fast,
                  width: AppSpacing.xxl,
                  height: AppSpacing.xxl,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: color),
                  ),
                  child: Center(
                    child: state == _StepState.done
                        ? Icon(
                            Icons.check_rounded,
                            size: AppSpacing.lg,
                            color: color,
                          )
                        : Text(
                            '$index',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: color,
                            ),
                          ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: AppSpacing.xxs,
                      margin: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style:
                                (state == _StepState.active
                                        ? theme.textTheme.titleMedium
                                        : theme.textTheme.titleSmall)
                                    ?.copyWith(color: color),
                          ),
                        ),
                        if (actionLabel != null)
                          TextButton(
                            onPressed: onAction,
                            child: Text(actionLabel!),
                          ),
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (child != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      child!,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinStepContent extends StatelessWidget {
  const _PinStepContent({
    required this.enabled,
    required this.includePhotos,
    required this.submitting,
    required this.onPinChanged,
    required this.onConfirmPinChanged,
    required this.onIncludePhotosChanged,
    required this.onComplete,
  });

  final bool enabled;
  final bool includePhotos;
  final bool submitting;
  final ValueChanged<String> onPinChanged;
  final ValueChanged<String> onConfirmPinChanged;
  final ValueChanged<bool?> onIncludePhotosChanged;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          enabled: enabled,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New app PIN',
            counterText: '',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
          onChanged: onPinChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          enabled: enabled,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Confirm PIN',
            counterText: '',
            prefixIcon: Icon(Icons.lock_reset_rounded),
          ),
          onChanged: onConfirmPinChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: includePhotos,
          onChanged: enabled ? onIncludePhotosChanged : null,
          title: const Text('Restore photo blobs'),
          subtitle: const Text('Turn off to restore metadata only.'),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: enabled ? onComplete : null,
            child: Text(submitting ? 'Restoring…' : 'Complete restore'),
          ),
        ),
      ],
    );
  }
}
