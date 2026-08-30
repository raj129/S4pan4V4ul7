import 'package:equatable/equatable.dart';

import '../domain/models/angle_unit.dart';
import '../domain/models/history_entry.dart';

/// Immutable snapshot of the calculator UI.
class CalculatorState extends Equatable {
  const CalculatorState({
    this.expression = '',
    this.preview = '',
    this.errorMessage,
    this.angleUnit = AngleUnit.degree,
    this.scientificExpanded = false,
    this.inverseMode = false,
    this.memoryActive = false,
    this.history = const <HistoryEntry>[],
    this.justEvaluated = false,
  });

  /// The expression exactly as typed, e.g. `12+3×4`.
  final String expression;

  /// Live result of [expression], or an empty string when it cannot be
  /// evaluated yet (incomplete input is not an error while typing).
  final String preview;

  /// Populated only after an explicit `=` on an invalid expression.
  final String? errorMessage;

  final AngleUnit angleUnit;

  /// Whether the scientific key rows are visible.
  final bool scientificExpanded;

  /// Whether the `INV` second-function layer is active.
  final bool inverseMode;

  final bool memoryActive;

  /// Most recent calculation first.
  final List<HistoryEntry> history;

  /// True immediately after `=`, so the next digit starts a new expression.
  final bool justEvaluated;

  /// Large primary text: the committed result after `=`, otherwise the input.
  String get displayText => expression.isEmpty ? '0' : expression;

  bool get hasError => errorMessage != null;

  CalculatorState copyWith({
    String? expression,
    String? preview,
    String? errorMessage,
    bool clearError = false,
    AngleUnit? angleUnit,
    bool? scientificExpanded,
    bool? inverseMode,
    bool? memoryActive,
    List<HistoryEntry>? history,
    bool? justEvaluated,
  }) {
    return CalculatorState(
      expression: expression ?? this.expression,
      preview: preview ?? this.preview,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      angleUnit: angleUnit ?? this.angleUnit,
      scientificExpanded: scientificExpanded ?? this.scientificExpanded,
      inverseMode: inverseMode ?? this.inverseMode,
      memoryActive: memoryActive ?? this.memoryActive,
      history: history ?? this.history,
      justEvaluated: justEvaluated ?? this.justEvaluated,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    expression,
    preview,
    errorMessage,
    angleUnit,
    scientificExpanded,
    inverseMode,
    memoryActive,
    history,
    justEvaluated,
  ];
}
