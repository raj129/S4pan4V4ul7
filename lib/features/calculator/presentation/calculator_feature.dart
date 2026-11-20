import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../application/calculator_cubit.dart';
import '../application/calculator_state.dart';
import '../domain/models/secret_entry_config.dart';
import 'responsive/calculator_responsive.dart';
import 'widgets/display_panel.dart';
import 'widgets/history_sheet.dart';
import 'widgets/keypad.dart';
import 'widgets/keypad_layouts.dart';
import 'widgets/memory_bar.dart';
import 'widgets/vault_trigger_detector.dart';

/// The calculator surface shown at the app root.
///
/// Owns a [CalculatorCubit] and composes the display, memory bar, scientific
/// rows and basic keypad. [onVaultTriggerRequested] fires when the hidden
/// press-and-hold gesture is completed, and [onStealthPinSubmitted] handles
/// direct-to-chat stealth PIN verification.
class CalculatorFeature extends StatefulWidget {
  const CalculatorFeature({
    required this.onVaultTriggerRequested,
    this.secretEntryConfig = const SecretEntryConfig(),
    this.onStealthPinSubmitted,
    super.key,
  });

  final VoidCallback onVaultTriggerRequested;
  final SecretEntryConfig secretEntryConfig;
  final Future<bool> Function(String pin)? onStealthPinSubmitted;

  @override
  State<CalculatorFeature> createState() => _CalculatorFeatureState();
}

class _CalculatorFeatureState extends State<CalculatorFeature> {
  late final CalculatorCubit _cubit;
  late final VaultTriggerDetector _vaultTrigger;

  @override
  void initState() {
    super.initState();
    _cubit = CalculatorCubit();
    _vaultTrigger = VaultTriggerDetector(
      config: widget.secretEntryConfig,
      onTriggered: () {
        if (mounted) widget.onVaultTriggerRequested();
      },
      onPinSubmitted: widget.onStealthPinSubmitted,
    );
  }

  @override
  void didUpdateWidget(covariant CalculatorFeature oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secretEntryConfig != widget.secretEntryConfig) {
      _vaultTrigger.updateConfig(widget.secretEntryConfig);
    }
  }

  @override
  void dispose() {
    _vaultTrigger.dispose();
    _cubit.close();
    super.dispose();
  }

  void _onKeyTap(CalcKey key) {
    _vaultTrigger.handleKeyTap(key.id);
    if (_vaultTrigger.consumeSuppressedTap(key.id)) return;
    switch (key.action) {
      case CalcAction.input:
        _cubit.input(key.payload!);
      case CalcAction.smartParen:
        _cubit.inputSmartParen();
      case CalcAction.equals:
        _cubit.equals();
      case CalcAction.clear:
        _cubit.clearAll();
      case CalcAction.backspace:
        _cubit.backspace();
      case CalcAction.toggleAngleUnit:
        _cubit.toggleAngleUnit();
      case CalcAction.toggleInverse:
        _cubit.toggleInverse();
      case CalcAction.memoryClear:
        _cubit.memoryClear();
      case CalcAction.memoryRecall:
        _cubit.memoryRecall();
      case CalcAction.memoryAdd:
        _cubit.memoryAdd();
      case CalcAction.memorySubtract:
        _cubit.memorySubtract();
    }
  }

  Future<void> _openHistory(CalculatorState state) {
    return HistorySheet.show(
      context,
      entries: state.history,
      onEntrySelected: _cubit.applyHistoryResult,
      onClear: _cubit.clearHistory,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CalculatorCubit>.value(
      value: _cubit,
      child: BlocBuilder<CalculatorCubit, CalculatorState>(
        bloc: _cubit,
        builder: (context, state) {
          final isDisplayCleared =
              state.expression.isEmpty || state.justEvaluated;
          _vaultTrigger.updateDisplayState(
            expression: state.expression,
            isCleared: isDisplayCleared,
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final layoutMode = CalculatorResponsive.getLayoutMode(
                constraints,
              );
              final compact = CalculatorResponsive.isCompact(constraints);
              final basicKeyHeight = CalculatorResponsive.calculateKeyHeight(
                constraints,
                state.scientificExpanded,
              );
              final sectionSpacing = CalculatorResponsive.sectionSpacing(
                layoutMode,
                compact,
              );
              final contentPadding = CalculatorResponsive.contentPadding(
                layoutMode,
              );

              final calculatorContent = Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DisplayPanel(
                    state: state,
                    compact: compact,
                    onHistoryTap: () => _openHistory(state),
                  ),
                  SizedBox(height: sectionSpacing),
                  MemoryBar(
                    memoryActive: state.memoryActive,
                    scientificExpanded: state.scientificExpanded,
                    onMemoryClear: () {
                      if (_vaultTrigger.consumeSuppressedTap(
                        kMemoryClearKeyId,
                      )) {
                        return;
                      }
                      _cubit.memoryClear();
                    },
                    onMemoryRecall: () {
                      if (_vaultTrigger.consumeSuppressedTap(
                        kMemoryRecallKeyId,
                      )) {
                        return;
                      }
                      _cubit.memoryRecall();
                    },
                    onMemoryAdd: () {
                      if (_vaultTrigger.consumeSuppressedTap(kMemoryAddKeyId)) {
                        return;
                      }
                      _cubit.memoryAdd();
                    },
                    onMemorySubtract: () {
                      if (_vaultTrigger.consumeSuppressedTap(
                        kMemorySubtractKeyId,
                      )) {
                        return;
                      }
                      _cubit.memorySubtract();
                    },
                    onToggleScientific: _cubit.toggleScientific,
                    onKeyPressStart: (keyId) => _vaultTrigger.handlePressStart(
                      keyId,
                      currentExpression: state.expression,
                      isDisplayCleared: isDisplayCleared,
                    ),
                    onKeyPressEnd: (keyId) =>
                        _vaultTrigger.handlePressEnd(keyId),
                    onKeyTap: (keyId) => _vaultTrigger.handleKeyTap(keyId),
                  ),
                  SizedBox(height: sectionSpacing),
                  if (state.scientificExpanded) ...<Widget>[
                    Keypad(
                      rows: scientificKeypadRows(
                        inverseMode: state.inverseMode,
                        angleUnit: state.angleUnit,
                      ),
                      keyHeight: compact ? 40 : 46,
                      spacing: 6,
                      onKeyTap: _onKeyTap,
                    ),
                    SizedBox(height: sectionSpacing),
                  ],
                  Keypad(
                    rows: basicKeypadRows(),
                    keyHeight: basicKeyHeight,
                    onKeyTap: _onKeyTap,
                    onKeyPressStart: (key) => _vaultTrigger.handlePressStart(
                      key.id,
                      currentExpression: state.expression,
                      isDisplayCleared: isDisplayCleared,
                    ),
                    onKeyPressEnd: (key) => _vaultTrigger.handlePressEnd(key.id),
                  ),
                ],
              );

              // Portrait mode: stick to bottom. Reuse the previously-verified
              // ConstrainedBox(minHeight) + Column pattern (safe inside a
              // SingleChildScrollView because it doesn't rely on
              // Spacer/Expanded, which need bounded constraints), and align
              // content to the end so it sits at the bottom of the viewport.
              if (layoutMode == CalculatorLayoutMode.portraitStickBottom) {
                return SingleChildScrollView(
                  padding: contentPadding,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[calculatorContent],
                    ),
                  ),
                );
              }

              // Landscape mode: expand to fill available space
              return SingleChildScrollView(
                padding: contentPadding,
                child: calculatorContent,
              );
            },
          );
        },
      ),
    );
  }
}
