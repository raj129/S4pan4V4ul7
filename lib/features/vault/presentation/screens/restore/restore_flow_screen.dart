import 'package:flutter/material.dart';

import 'package:photo_vault/features/vault/application/services/restore_flow_service.dart';
import 'package:photo_vault/core/widgets/app_state_views.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import 'package:photo_vault/core/presentation/theme/app_colors.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';

class RestoreFlowScreen extends StatefulWidget {
  const RestoreFlowScreen({
    required this.authRepository,
    required this.restoreFlowService,
    required this.onRestoreCompleted,
    super.key,
  });
  final AuthRepository authRepository;
  final RestoreFlowService restoreFlowService;
  final Future<void> Function(String vaultId) onRestoreCompleted;

  @override
  State<RestoreFlowScreen> createState() => _RestoreFlowScreenState();
}

class _RestoreFlowScreenState extends State<RestoreFlowScreen> {
  bool _loading = true;
  bool _signedIn = false;
  bool _loadingVaults = false;
  bool _restoreCompleted = false;
  bool _includePhotos = true;
  bool _submitting = false;
  final _originalPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  String _originalPin = '';
  String _newPin = '';
  String _confirmPin = '';
  String? _selectedVaultId;
  String? _completionMessage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    var signedIn = false;
    String? error;
    try {
      signedIn = await widget.authRepository.isSignedIn();
      if (signedIn) {
        await _loadVaults();
      }
    } catch (e) {
      error = _briefError(e);
    }
    if (!mounted) return;
    setState(() {
      _signedIn = signedIn;
      _error = error;
      _loading = false;
    });
  }

  Future<void> _loadVaults() async {
    final ids = await widget.restoreFlowService.listVaultIds();
    if (!mounted) return;
    setState(() {
      _selectedVaultId = ids.length == 1 ? ids.single : null;
      _vaultIds = ids;
    });
  }

  List<String> _vaultIds = const [];

  Future<void> _refreshVaults() async {
    setState(() {
      _loadingVaults = true;
      _error = null;
    });
    try {
      await _loadVaults();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _briefError(e));
    } finally {
      if (mounted) setState(() => _loadingVaults = false);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authRepository.signInWithGoogle();
      if (!mounted) return;
      setState(() => _signedIn = true);
      await _refreshVaults();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Google sign-in failed: ${_briefError(e)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _confirmVaultSwitch(String selectedVaultId) async {
    final current = await widget.restoreFlowService.activeVaultId();
    if (!mounted) return false;
    if (current == null || current == selectedVaultId) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Switch active vault?'),
        content: Text(
          'This device currently has vault ${_shortId(current)}. Recovery will '
          'switch to vault ${_shortId(selectedVaultId)}. The current local data '
          'will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Switch vault'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _completeRestore() async {
    final vaultId = _selectedVaultId;
    if (vaultId == null) {
      setState(() => _error = 'Choose a vault backup first.');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(_originalPin)) {
      setState(() => _error = 'Enter the original 4-digit vault PIN.');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(_newPin) || _newPin != _confirmPin) {
      setState(() => _error = 'Enter matching new 4-digit PIN values.');
      return;
    }
    try {
      if (!await _confirmVaultSwitch(vaultId) || !mounted) return;
    } catch (e) {
      if (mounted) setState(() => _error = _briefError(e));
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.restoreFlowService.restoreVault(
        vaultId: vaultId,
        originalPin: _originalPin,
        newPin: _newPin,
      );
      final completion = <String>[
        'Vault key recovered. Keep the original backup PIN for future restores',
      ];
      if (_includePhotos) {
        try {
          final photos = await widget.restoreFlowService.restorePhotos(
            includePhotos: true,
          );
          if (photos.restored > 0) {
            completion.add('${photos.restored} vault photos restored');
          } else if (!photos.foundBackup) {
            completion.add('no vault-photo backup found');
          }
          if (photos.alreadyPresent > 0) {
            completion.add('${photos.alreadyPresent} photos already present');
          }
          if (photos.unavailable > 0) {
            completion.add('${photos.unavailable} photos unavailable');
          }
          if (photos.failures.isNotEmpty) {
            completion.add(
              '${photos.failures.length} backup copies could not be read',
            );
          }
        } catch (e) {
          completion.add('photos could not be restored: ${_briefError(e)}');
        }
      } else {
        completion.add('photo restore skipped');
      }
      if (!mounted) return;
      setState(() {
        _restoreCompleted = true;
        _completionMessage = '${completion.join('. ')}.';
        _originalPin = '';
        _newPin = '';
        _confirmPin = '';
      });
      _originalPinController.clear();
      _newPinController.clear();
      _confirmPinController.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _briefError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openRestoredVault() async {
    final vaultId = _selectedVaultId;
    if (!_restoreCompleted || vaultId == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onRestoreCompleted(vaultId);
    } catch (e) {
      if (mounted) setState(() => _error = _briefError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static String _shortId(String id) =>
      id.length <= 8 ? id : '${id.substring(0, 8)}…';

  static String _briefError(Object error) {
    final message = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (message.contains('Google Drive API has not been used') ||
        message.contains('drive.googleapis.com/overview')) {
      return 'Google Drive API is disabled for this project. Enable '
          'drive.googleapis.com in Google Cloud, then retry.';
    }
    return message.length > 200 ? '${message.substring(0, 200)}…' : message;
  }

  @override
  void dispose() {
    _originalPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
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
            'Choose a Google vault, enter the PIN used when it was backed up, '
            'and set a new PIN for this device. Recovery preserves the vault ID.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_completionMessage != null) ...[
            const SizedBox(height: AppSpacing.lg),
            InfoBanner(
              message: _completionMessage!,
              tone: InfoBannerTone.success,
            ),
          ],
          if (_error != null && _selectedVaultId == null) ...[
            const SizedBox(height: AppSpacing.lg),
            InfoBanner(message: _error!, tone: InfoBannerTone.error),
          ],
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
                title: 'Choose a vault backup',
                subtitle: !_signedIn
                    ? 'Sign in first.'
                    : _loadingVaults
                    ? 'Checking Google Drive…'
                    : _vaultIds.isEmpty
                    ? 'No vault backups were found for this account.'
                    : _vaultIds.length == 1
                    ? 'Vault ${_shortId(_vaultIds.single)} is available.'
                    : '${_vaultIds.length} vault backups are available.',
                state: _selectedVaultId != null
                    ? _StepState.done
                    : (_signedIn ? _StepState.active : _StepState.pending),
                actionLabel: _signedIn && !_loadingVaults
                    ? 'Check again'
                    : null,
                onAction: _signedIn && !_loadingVaults ? _refreshVaults : null,
                child: _vaultIds.length == 1
                    ? Text('Vault ${_shortId(_vaultIds.single)}')
                    : _vaultIds.length > 1
                    ? RadioGroup<String>(
                        groupValue: _selectedVaultId,
                        onChanged: (value) {
                          if (!_submitting) {
                            setState(() => _selectedVaultId = value);
                          }
                        },
                        child: Column(
                          children: [
                            for (final id in _vaultIds)
                              RadioListTile<String>(
                                enabled: !_submitting,
                                contentPadding: EdgeInsets.zero,
                                title: Text('Vault ${_shortId(id)}'),
                                value: id,
                              ),
                          ],
                        ),
                      )
                    : null,
              ),
              _RestoreStepRow(
                index: 3,
                title: 'Verify the backup PIN and set a new PIN',
                subtitle:
                    'The PIN used at backup time decrypts the key. The new PIN '
                    'protects it on this device; the Drive copy still uses the '
                    'original backup PIN.',
                state: _restoreCompleted
                    ? _StepState.done
                    : (_selectedVaultId != null
                          ? _StepState.active
                          : _StepState.pending),
                isLast: false,
                child: _PinStepContent(
                  enabled:
                      _selectedVaultId != null &&
                      !_submitting &&
                      !_restoreCompleted,
                  includePhotos: _includePhotos,
                  submitting: _submitting,
                  errorMessage: _selectedVaultId == null ? null : _error,
                  originalPinController: _originalPinController,
                  newPinController: _newPinController,
                  confirmPinController: _confirmPinController,
                  onOriginalPinChanged: (v) => _originalPin = v,
                  onNewPinChanged: (v) => _newPin = v,
                  onConfirmPinChanged: (v) => _confirmPin = v,
                  onIncludePhotosChanged: (v) =>
                      setState(() => _includePhotos = v ?? true),
                  onComplete: _completeRestore,
                ),
              ),
              _RestoreStepRow(
                index: 4,
                title: 'Open recovered vault',
                subtitle: _completionMessage ?? 'Complete recovery first.',
                state: _restoreCompleted
                    ? _StepState.active
                    : _StepState.pending,
                isLast: true,
                actionLabel: _restoreCompleted ? 'Open vault' : null,
                onAction: _restoreCompleted ? _openRestoredVault : null,
              ),
            ],
          ),
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
    required this.errorMessage,
    required this.originalPinController,
    required this.newPinController,
    required this.confirmPinController,
    required this.onOriginalPinChanged,
    required this.onNewPinChanged,
    required this.onConfirmPinChanged,
    required this.onIncludePhotosChanged,
    required this.onComplete,
  });

  final bool enabled;
  final bool includePhotos;
  final bool submitting;
  final String? errorMessage;
  final TextEditingController originalPinController;
  final TextEditingController newPinController;
  final TextEditingController confirmPinController;
  final ValueChanged<String> onOriginalPinChanged;
  final ValueChanged<String> onNewPinChanged;
  final ValueChanged<String> onConfirmPinChanged;
  final ValueChanged<bool?> onIncludePhotosChanged;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: originalPinController,
          enabled: enabled,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'PIN from backup time',
            counterText: '',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
          onChanged: onOriginalPinChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: newPinController,
          enabled: enabled,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New app PIN for this device',
            counterText: '',
            prefixIcon: Icon(Icons.lock_reset_rounded),
          ),
          onChanged: onNewPinChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: confirmPinController,
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
          title: const Text('Restore encrypted vault photos'),
          subtitle: const Text(
            'Restore photos from the vault backup if available.',
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBanner(message: errorMessage!, tone: InfoBannerTone.error),
        ],
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: enabled ? onComplete : null,
            child: Text(submitting ? 'Restoring…' : 'Restore vault'),
          ),
        ),
      ],
    );
  }
}
