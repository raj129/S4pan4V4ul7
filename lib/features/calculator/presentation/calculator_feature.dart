import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../application/calculator_cubit.dart';
import '../application/calculator_state.dart';
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
/// press-and-hold gesture is completed.
class CalculatorFeature extends StatefulWidget {
  const CalculatorFeature({required this.onVaultTriggerRequested, super.key});

  final VoidCallback onVaultTriggerRequested;

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
      onTriggered: () {
        if (mounted) widget.onVaultTriggerRequested();
      },
    );
  }

  @override
  void dispose() {
    _vaultTrigger.dispose();
    _cubit.close();
    super.dispose();
  }

  void _onKeyTap(CalcKey key) {
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
        builder: (context, state) => LayoutBuilder(
          builder: (context, constraints) {
            final layoutMode = CalculatorResponsive.getLayoutMode(constraints);
            final compact = CalculatorResponsive.isCompact(constraints);
            final basicKeyHeight =
                CalculatorResponsive.calculateKeyHeight(constraints, state.scientificExpanded);
            final sectionSpacing =
                CalculatorResponsive.sectionSpacing(layoutMode, compact);
            final contentPadding =
                CalculatorResponsive.contentPadding(layoutMode);

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
                  onMemoryClear: _cubit.memoryClear,
                  onMemoryRecall: _cubit.memoryRecall,
                  onMemoryAdd: _cubit.memoryAdd,
                  onMemorySubtract: _cubit.memorySubtract,
                  onToggleScientific: _cubit.toggleScientific,
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
                  onKeyPressStart: (key) =>
                      _vaultTrigger.handlePressStart(key.id),
                  onKeyPressEnd: (key) =>
                      _vaultTrigger.handlePressEnd(key.id),
                ),
              ],
            );

            // Portrait mode: stick to bottom with spacer above
            if (layoutMode == CalculatorLayoutMode.portraitStickBottom) {
              return SingleChildScrollView(
                padding: contentPadding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    children: <Widget>[
                      Spacer(),
                      calculatorContent,
                    ],
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
        ),
      ),
    );
  }
}
