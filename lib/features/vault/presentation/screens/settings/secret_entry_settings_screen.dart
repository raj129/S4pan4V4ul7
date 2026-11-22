import 'dart:async';

import 'package:flutter/material.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import 'package:photo_vault/features/calculator/domain/models/secret_entry_config.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';

class SecretEntrySettingsScreen extends StatefulWidget {
  const SecretEntrySettingsScreen({
    required this.settingsRepository,
    required this.onSettingsChanged,
    super.key,
  });

  final SettingsRepository settingsRepository;
  final Future<void> Function() onSettingsChanged;

  @override
  State<SecretEntrySettingsScreen> createState() =>
      _SecretEntrySettingsScreenState();
}

class _SecretEntrySettingsScreenState extends State<SecretEntrySettingsScreen> {
  SecretEntryConfig _config = const SecretEntryConfig();
  late final TextEditingController _expressionController;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _expressionController = TextEditingController(
      text: _config.secretExpression,
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _expressionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loaded = await widget.settingsRepository.getSecretEntryConfig();
    if (!mounted) return;
    setState(() {
      _config = loaded;
      _expressionController.text = loaded.secretExpression;
      _loaded = true;
    });
  }

  Future<void> _saveConfig(SecretEntryConfig next) async {
    setState(() => _config = next);
    await widget.settingsRepository.setSecretEntryConfig(next);
    await widget.onSettingsChanged();
  }

  Future<void> _selectMethod(SecretEntryMethod method) async {
    if (_config.method == method && _config.oneHandedEnabled) return;
    final next = SecretEntryConfig.defaultsFor(
      method,
      oneHandedEnabled: true,
      defaultPrimaryKeyId: _config.defaultPrimaryKeyId,
      defaultSecondaryKeyId: _config.defaultSecondaryKeyId,
    );
    _expressionController.text = next.secretExpression;
    await _saveConfig(next);
  }

  Future<void> _pickKey({
    required String title,
    required String currentKeyId,
    required ValueChanged<String> onSelected,
  }) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _CalculatorKeyPickerSheet(title: title, selectedKeyId: currentKeyId),
    );
    if (chosen == null || chosen == currentKeyId) return;
    onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final oneHandedEnabled = _config.oneHandedEnabled;

    final defaultKey1 = labelForCalcKeyId(_config.defaultPrimaryKeyId);
    final defaultKey2 = labelForCalcKeyId(_config.defaultSecondaryKeyId);

    return Scaffold(
      appBar: AppBar(title: const Text('Secret entry')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: InfoBanner(
                    message:
                        'Default entry (holding $defaultKey1 and $defaultKey2 '
                        'together) is always active as a fallback. Enable a '
                        'one-handed method below as a second way to enter.',
                    tone: InfoBannerTone.info,
                  ),
                ),
                const SectionHeader('Default two-key hold (always active)'),
                SettingsCard(
                  children: [
                    _KeyPickerTile(
                      key: const Key('default-primary-key-picker'),
                      icon: Icons.looks_one_outlined,
                      title: 'First hold key',
                      subtitle:
                          'Hold together with the second key (default: 7).',
                      keyId: _config.defaultPrimaryKeyId,
                      onTap: () => _pickKey(
                        title: 'Choose default first hold key',
                        currentKeyId: _config.defaultPrimaryKeyId,
                        onSelected: (id) => unawaited(
                          _saveConfig(_config.copyWith(defaultPrimaryKeyId: id)),
                        ),
                      ),
                    ),
                    _KeyPickerTile(
                      key: const Key('default-secondary-key-picker'),
                      icon: Icons.looks_two_outlined,
                      title: 'Second hold key',
                      subtitle:
                          'Hold together with the first key (default: =).',
                      keyId: _config.defaultSecondaryKeyId,
                      onTap: () => _pickKey(
                        title: 'Choose default second hold key',
                        currentKeyId: _config.defaultSecondaryKeyId,
                        onSelected: (id) => unawaited(
                          _saveConfig(
                            _config.copyWith(defaultSecondaryKeyId: id),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SectionHeader('One-handed mode'),
                SettingsCard(
                  children: [
                    SwitchListTile(
                      key: const Key('custom-secret-entry-switch'),
                      secondary: const Icon(Icons.touch_app_outlined),
                      title: const Text('Enable one-handed entry'),
                      subtitle: Text(
                        oneHandedEnabled
                            ? 'Active alongside $defaultKey1 & $defaultKey2: ${_config.method.shortSummary}'
                            : 'Only $defaultKey1 & $defaultKey2 hold is active.',
                      ),
                      value: oneHandedEnabled,
                      onChanged: (enabled) {
                        unawaited(
                          _saveConfig(
                            _config.copyWith(oneHandedEnabled: enabled),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (oneHandedEnabled) ...[
                  const SectionHeader('One-handed method'),
                  SettingsCard(
                    children: [
                      for (final method in SecretEntryMethodX.oneHandedMethods)
                        _MethodOptionTile(
                          method: method,
                          selected: _config.method == method,
                          onTap: () => unawaited(_selectMethod(method)),
                        ),
                    ],
                  ),
                  const SectionHeader('Configure keys & behavior'),
                  SettingsCard(children: _buildMethodConfiguration(theme, cs)),
                ],
              ],
            ),
    );
  }

  List<Widget> _buildMethodConfiguration(ThemeData theme, ColorScheme cs) {
    switch (_config.method) {
      case SecretEntryMethod.simultaneousHold:
        return [
          _KeyPickerTile(
            key: const Key('primary-key-picker'),
            icon: Icons.looks_one_outlined,
            title: 'First hold key',
            subtitle: 'Hold together with the second key for 1.2s.',
            keyId: _config.primaryKeyId,
            onTap: () => _pickKey(
              title: 'Choose first hold key',
              currentKeyId: _config.primaryKeyId,
              onSelected: (id) =>
                  unawaited(_saveConfig(_config.copyWith(primaryKeyId: id))),
            ),
          ),
          _KeyPickerTile(
            key: const Key('secondary-key-picker'),
            icon: Icons.looks_two_outlined,
            title: 'Second hold key',
            subtitle: 'Hold together with the first key.',
            keyId: _config.secondaryKeyId,
            onTap: () => _pickKey(
              title: 'Choose second hold key',
              currentKeyId: _config.secondaryKeyId,
              onSelected: (id) =>
                  unawaited(_saveConfig(_config.copyWith(secondaryKeyId: id))),
            ),
          ),
        ];

      case SecretEntryMethod.holdPinConfirm:
        return [
          _KeyPickerTile(
            key: const Key('primary-key-picker'),
            icon: Icons.pan_tool_alt_outlined,
            title: 'Hold key to start',
            subtitle:
                'Hold this key (~0.8s), release, then type your 4-digit PIN.',
            keyId: _config.primaryKeyId,
            onTap: () => _pickKey(
              title: 'Choose hold key',
              currentKeyId: _config.primaryKeyId,
              onSelected: (id) =>
                  unawaited(_saveConfig(_config.copyWith(primaryKeyId: id))),
            ),
          ),
          _KeyPickerTile(
            key: const Key('confirm-key-picker'),
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Confirm key (opens Chat)',
            subtitle:
                'Press this key after typing your PIN to unlock directly to Chat.',
            keyId: _config.confirmKeyId,
            onTap: () => _pickKey(
              title: 'Choose confirm key',
              currentKeyId: _config.confirmKeyId,
              onSelected: (id) =>
                  unawaited(_saveConfig(_config.copyWith(confirmKeyId: id))),
            ),
          ),
        ];

      case SecretEntryMethod.sequentialHold:
        return [
          _KeyPickerTile(
            key: const Key('primary-key-picker'),
            icon: Icons.timer_outlined,
            title: 'First key (Hold)',
            subtitle: 'Hold this key (~0.8s), then release.',
            keyId: _config.primaryKeyId,
            onTap: () => _pickKey(
              title: 'Choose key to hold first',
              currentKeyId: _config.primaryKeyId,
              onSelected: (id) =>
                  unawaited(_saveConfig(_config.copyWith(primaryKeyId: id))),
            ),
          ),
          _KeyPickerTile(
            key: const Key('secondary-key-picker'),
            icon: Icons.touch_app_outlined,
            title: 'Second key (Tap)',
            subtitle: 'Tap this key within 1.5s after releasing the first key.',
            keyId: _config.secondaryKeyId,
            onTap: () => _pickKey(
              title: 'Choose key to tap second',
              currentKeyId: _config.secondaryKeyId,
              onSelected: (id) =>
                  unawaited(_saveConfig(_config.copyWith(secondaryKeyId: id))),
            ),
          ),
          SwitchListTile(
            key: const Key('require-cleared-display-switch'),
            secondary: const Icon(Icons.backspace_outlined),
            title: const Text('Require cleared display'),
            subtitle: const Text(
              'Only arm when calculator display is empty or cleared (0).',
            ),
            value: _config.requireClearedDisplay,
            onChanged: (value) => unawaited(
              _saveConfig(_config.copyWith(requireClearedDisplay: value)),
            ),
          ),
        ];

      case SecretEntryMethod.secretExpressionHold:
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: TextField(
              key: const Key('secret-expression-field'),
              controller: _expressionController,
              decoration: const InputDecoration(
                labelText: 'Secret number or expression',
                hintText: 'e.g. 77 or 1337',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                final trimmed = value.trim();
                if (trimmed.isNotEmpty) {
                  unawaited(
                    _saveConfig(_config.copyWith(secretExpression: trimmed)),
                  );
                }
              },
            ),
          ),
          _KeyPickerTile(
            key: const Key('primary-key-picker'),
            icon: Icons.pan_tool_alt_outlined,
            title: 'Hold key',
            subtitle:
                'Long-press this key (~1s) while the secret expression is on screen.',
            keyId: _config.primaryKeyId,
            onTap: () => _pickKey(
              title: 'Choose hold key',
              currentKeyId: _config.primaryKeyId,
              onSelected: (id) =>
                  unawaited(_saveConfig(_config.copyWith(primaryKeyId: id))),
            ),
          ),
        ];

      case SecretEntryMethod.multiTapHold:
        return [
          _KeyPickerTile(
            key: const Key('primary-key-picker'),
            icon: Icons.ads_click_rounded,
            title: 'Trigger key',
            subtitle: 'Tap this key quickly, then hold on the final press.',
            keyId: _config.primaryKeyId,
            onTap: () => _pickKey(
              title: 'Choose trigger key',
              currentKeyId: _config.primaryKeyId,
              onSelected: (id) =>
                  unawaited(_saveConfig(_config.copyWith(primaryKeyId: id))),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.repeat_rounded),
            title: const Text('Quick taps before hold'),
            subtitle: Text(
              'Tap ${_config.tapCount} times quickly, then hold on press #${_config.tapCount + 1}.',
            ),
            trailing: DropdownButton<int>(
              key: const Key('tap-count-dropdown'),
              value: _config.tapCount,
              onChanged: (count) {
                if (count != null) {
                  unawaited(_saveConfig(_config.copyWith(tapCount: count)));
                }
              },
              items: [2, 3, 4, 5, 6]
                  .map(
                    (count) => DropdownMenuItem<int>(
                      value: count,
                      child: Text('$count taps'),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ];

      case SecretEntryMethod.secretMathEquation:
        return [
          _KeyPickerTile(
            key: const Key('primary-key-picker'),
            icon: Icons.calculate_outlined,
            title: 'Hold key',
            subtitle:
                'Type your PIN (or an equation ending in your 4-digit PIN, e.g. '
                '42+1958) and long-press this key (~1s) to jump straight to Chat. '
                'Invalid PINs calculate normally.',
            keyId: _config.primaryKeyId,
            onTap: () => _pickKey(
              title: 'Choose hold key',
              currentKeyId: _config.primaryKeyId,
              onSelected: (id) =>
                  unawaited(_saveConfig(_config.copyWith(primaryKeyId: id))),
            ),
          ),
        ];
    }
  }
}

class _MethodOptionTile extends StatelessWidget {
  const _MethodOptionTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final SecretEntryMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      key: Key('secret-method-${method.id}'),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(method.title),
      subtitle: Text(method.shortSummary),
      selected: selected,
      onTap: onTap,
    );
  }
}

class _KeyPickerTile extends StatelessWidget {
  const _KeyPickerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.keyId,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String keyId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Chip(
        label: Text(
          labelForCalcKeyId(keyId),
          style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
        ),
      ),
      onTap: onTap,
    );
  }
}

class _CalculatorKeyPickerSheet extends StatelessWidget {
  const _CalculatorKeyPickerSheet({
    required this.title,
    required this.selectedKeyId,
  });

  final String title;
  final String selectedKeyId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final memoryKeys = selectableCalculatorKeys
        .where((k) => k.category == 'Memory')
        .toList(growable: false);
    final keypadKeys = selectableCalculatorKeys
        .where((k) => k.category != 'Memory')
        .toList(growable: false);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Memory bar',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                for (var i = 0; i < memoryKeys.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _KeyChipButton(
                      option: memoryKeys[i],
                      selected: memoryKeys[i].id == selectedKeyId,
                      onTap: () => Navigator.of(context).pop(memoryKeys[i].id),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Calculator keypad',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: AppSpacing.xs,
                crossAxisSpacing: AppSpacing.xs,
                childAspectRatio: 1.7,
              ),
              itemCount: keypadKeys.length,
              itemBuilder: (context, index) {
                final option = keypadKeys[index];
                return _KeyChipButton(
                  option: option,
                  selected: option.id == selectedKeyId,
                  onTap: () => Navigator.of(context).pop(option.id),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyChipButton extends StatelessWidget {
  const _KeyChipButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final CalcKeyOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: Key('picker-key-${option.id}'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Text(
            option.label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? cs.onPrimaryContainer : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
