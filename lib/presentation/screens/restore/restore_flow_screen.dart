import 'package:flutter/material.dart';

import '../../../application/services/restore_flow_service.dart';
import '../../../domain/repositories/auth_repository.dart';

class RestoreFlowScreen extends StatefulWidget {
  const RestoreFlowScreen({
    required this.authRepository,
    required this.restoreFlowService,
    required this.onRestoreCompleted,
    super.key,
  });

  final AuthRepository authRepository;
  final RestoreFlowService restoreFlowService;
  final Future<void> Function(String pin, bool includePhotos) onRestoreCompleted;

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
        _error = 'No backup VMK found. A new encryption key will be created when you enter your PIN below.';
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
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Restore Vault')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StepTile(
            title: '1. Sign in with Google',
            done: _signedIn,
            actionLabel: _signedIn ? null : 'Sign in',
            onAction: _signedIn || _submitting ? null : _signIn,
          ),
          _StepTile(
            title: '2. Fetch backup manifest',
            done: _manifestFetched,
            actionLabel: _signedIn && _manifestAvailable && !_manifestFetched
                ? 'Fetch'
                : null,
            onAction: (_signedIn && _manifestAvailable && !_manifestFetched && !_submitting)
                ? _fetchManifest
                : null,
            subtitle: !_signedIn
                ? 'Sign in first.'
                : (!_manifestAvailable ? 'No backup manifest found for this account.' : null),
          ),
          _StepTile(
            title: '3. Restore encrypted VMK backup',
            done: _vmkRestored,
            actionLabel: _manifestFetched && !_vmkRestored ? 'Restore VMK' : null,
            onAction: (_manifestFetched && !_vmkRestored && !_submitting)
                ? _restoreVmk
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            '4. Create new local PIN (re-wrap key locally)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            enabled: _vmkRestored && !_submitting,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New app PIN',
              counterText: '',
            ),
            onChanged: (v) => _pin = v,
          ),
          TextField(
            enabled: _vmkRestored && !_submitting,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm PIN',
              counterText: '',
            ),
            onChanged: (v) => _confirmPin = v,
          ),
          CheckboxListTile(
            value: _includePhotos,
            onChanged: _vmkRestored && !_submitting
                ? (v) => setState(() => _includePhotos = v ?? true)
                : null,
            title: const Text('Restore photo blobs'),
            subtitle: const Text('Turn off to restore metadata only.'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: (_vmkRestored && !_submitting) ? _completeRestore : null,
            child: Text(_submitting ? 'Restoring...' : 'Complete restore'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.title,
    required this.done,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final bool done;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: done ? Colors.green : null,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: actionLabel == null
          ? null
          : TextButton(onPressed: onAction, child: Text(actionLabel!)),
    );
  }
}
