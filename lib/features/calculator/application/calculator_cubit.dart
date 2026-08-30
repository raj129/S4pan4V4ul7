import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/calculator_engine.dart';
import '../domain/models/history_entry.dart';
import '../domain/models/token.dart';
import 'calculator_state.dart';
import 'history_store.dart';
import 'memory_store.dart';

/// Orchestrates expression editing, live preview, history and memory.
class CalculatorCubit extends Cubit<CalculatorState> {
  CalculatorCubit({
    CalculatorEngine? engine,
    HistoryStore? historyStore,
    MemoryStore? memoryStore,
    DateTime Function()? now,
  }) : _engine = engine ?? const CalculatorEngine(),
       _history = historyStore ?? HistoryStore(),
       _memory = memoryStore ?? MemoryStore(),
       _now = now ?? DateTime.now,
       super(const CalculatorState());

  final CalculatorEngine _engine;
  final HistoryStore _history;
  final MemoryStore _memory;
  final DateTime Function() _now;

  static const Set<String> _digits = <String>{
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
  };

  /// Appends [input] to the expression, applying editing rules such as
  /// operator replacement and single-decimal-point enforcement.
  void input(String input) {
    if (input.isEmpty) return;

    var expression = state.expression;

    if (state.justEvaluated) {
      // Digits, constants, functions and `(` start over; operators and
      // postfixes continue from the previous result.
      final continues =
          _isOperatorSymbol(input) || input == '!' || input == '%';
      expression = continues ? expression : '';
    }

    if (_isOperatorSymbol(input)) {
      expression = _appendOperator(expression, input);
    } else if (input == '.') {
      expression = _appendDecimal(expression);
    } else if (input == 'E') {
      if (!_endsWithNumber(expression) || _currentNumber(expression).contains('E')) {
        return;
      }
      expression += 'E';
    } else if (input == ')') {
      if (_openParenCount(expression) == 0) return;
      if (expression.isEmpty || _endsWithOpenOperator(expression)) return;
      expression += ')';
    } else {
      expression += input;
    }

    _emitExpression(expression);
  }

  /// Inserts `(` or `)` depending on the current parenthesis balance.
  void inputSmartParen() {
    final expression = state.justEvaluated ? '' : state.expression;
    final canClose =
        _openParenCount(expression) > 0 &&
        expression.isNotEmpty &&
        !_endsWithOpenOperator(expression);
    input(canClose ? ')' : '(');
  }

  void backspace() {
    if (state.justEvaluated) {
      _emitExpression('');
      return;
    }
    final expression = state.expression;
    if (expression.isEmpty) return;

    // Remove whole function names rather than a single character.
    for (final name in _removableNames) {
      if (expression.endsWith(name)) {
        _emitExpression(
          expression.substring(0, expression.length - name.length),
        );
        return;
      }
    }
    _emitExpression(expression.substring(0, expression.length - 1));
  }

  void clearAll() {
    emit(
      state.copyWith(
        expression: '',
        preview: '',
        clearError: true,
        justEvaluated: false,
      ),
    );
  }

  void equals() {
    final expression = state.expression;
    if (expression.isEmpty) return;

    final result = _engine.evaluate(expression, state.angleUnit);
    if (!result.isSuccess) {
      emit(
        state.copyWith(
          preview: '',
          errorMessage: result.error!.message,
          justEvaluated: false,
        ),
      );
      return;
    }

    final formatted = result.formatted!;
    _history.add(
      HistoryEntry(
        expression: expression,
        result: formatted,
        timestamp: _now(),
      ),
    );

    emit(
      state.copyWith(
        expression: _engine.formatter.formatRaw(result.value!),
        preview: '',
        clearError: true,
        history: _history.entries,
        justEvaluated: true,
      ),
    );
  }

  void toggleAngleUnit() {
    emit(state.copyWith(angleUnit: state.angleUnit.toggled));
    _refreshPreview();
  }

  void toggleScientific() {
    emit(state.copyWith(scientificExpanded: !state.scientificExpanded));
  }

  void toggleInverse() {
    emit(state.copyWith(inverseMode: !state.inverseMode));
  }

  void memoryClear() {
    _memory.clear();
    emit(state.copyWith(memoryActive: false));
  }

  void memoryRecall() {
    if (!_memory.hasValue) return;
    input(_engine.formatter.formatRaw(_memory.value));
  }

  void memoryAdd() => _memoryApply(add: true);

  void memorySubtract() => _memoryApply(add: false);

  void _memoryApply({required bool add}) {
    final value = _currentValue();
    if (value == null) return;
    if (add) {
      _memory.add(value);
    } else {
      _memory.subtract(value);
    }
    emit(state.copyWith(memoryActive: _memory.hasValue, justEvaluated: true));
  }

  void clearHistory() {
    _history.clear();
    emit(state.copyWith(history: _history.entries));
  }

  /// Reuses a past result as the current expression.
  void applyHistoryResult(HistoryEntry entry) {
    _emitExpression(entry.result.replaceAll(',', ''));
  }

  double? _currentValue() {
    if (state.expression.isEmpty) return null;
    final result = _engine.evaluate(state.expression, state.angleUnit);
    return result.isSuccess ? result.value : null;
  }

  void _emitExpression(String expression) {
    emit(
      state.copyWith(
        expression: expression,
        preview: _previewFor(expression),
        clearError: true,
        justEvaluated: false,
      ),
    );
  }

  void _refreshPreview() {
    emit(state.copyWith(preview: _previewFor(state.expression)));
  }

  /// A preview is shown only when the expression is complete enough to
  /// evaluate and differs from what is already displayed.
  String _previewFor(String expression) {
    if (expression.isEmpty) return '';
    if (_isNumericLiteral(expression)) return '';
    final result = _engine.evaluate(expression, state.angleUnit);
    if (!result.isSuccess) return '';
    return result.formatted!;
  }

  bool _isNumericLiteral(String expression) =>
      double.tryParse(expression.replaceAll(',', '')) != null;

  String _appendOperator(String expression, String symbol) {
    if (expression.isEmpty) {
      // Only a leading minus makes sense on an empty expression.
      return symbol == '-' ? '-' : expression;
    }
    if (_endsWithOperator(expression)) {
      final trailing = _trailingOperator(expression)!;
      // `5×` followed by `-` becomes `5×-` (negation) rather than a swap.
      if (symbol == '-' && trailing != '-' && trailing != '+') {
        return '$expression-';
      }
      return expression.substring(0, expression.length - trailing.length) +
          symbol;
    }
    if (expression.endsWith('(')) {
      return symbol == '-' ? '$expression-' : expression;
    }
    return expression + symbol;
  }

  String _appendDecimal(String expression) {
    final current = _currentNumber(expression);
    if (current.contains('.') || current.contains('E')) return expression;
    if (current.isEmpty) return '${expression}0.';
    return '$expression.';
  }

  /// The digits of the number currently being typed at the end of the input.
  String _currentNumber(String expression) {
    var index = expression.length;
    while (index > 0) {
      final char = expression[index - 1];
      final isNumeric =
          _digits.contains(char) ||
          char == '.' ||
          char == 'E' ||
          (char == '-' &&
              index >= 2 &&
              expression[index - 2] == 'E');
      if (!isNumeric) break;
      index--;
    }
    return expression.substring(index);
  }

  bool _endsWithNumber(String expression) =>
      expression.isNotEmpty && _digits.contains(expression[expression.length - 1]);

  bool _isOperatorSymbol(String symbol) => kOperators.containsKey(symbol);

  String? _trailingOperator(String expression) {
    for (final symbol in kOperators.keys) {
      if (expression.endsWith(symbol)) return symbol;
    }
    return null;
  }

  bool _endsWithOperator(String expression) =>
      _trailingOperator(expression) != null;

  /// True when the expression cannot be closed yet, e.g. `2×` or `sin(`.
  bool _endsWithOpenOperator(String expression) =>
      _endsWithOperator(expression) || expression.endsWith('(');

  int _openParenCount(String expression) {
    var depth = 0;
    for (final char in expression.split('')) {
      if (char == '(') depth++;
      if (char == ')') depth--;
    }
    return depth < 0 ? 0 : depth;
  }

  /// Multi-character tokens that backspace should delete atomically.
  static final List<String> _removableNames = <String>[
    ...kFunctions.map((name) => '$name('),
    ...kFunctions,
    'mod',
  ]..sort((a, b) => b.length.compareTo(a.length));
}
