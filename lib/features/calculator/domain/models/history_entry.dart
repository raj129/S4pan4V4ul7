import 'package:equatable/equatable.dart';

/// A single completed calculation kept in the session-scoped history.
class HistoryEntry extends Equatable {
  const HistoryEntry({
    required this.expression,
    required this.result,
    required this.timestamp,
  });

  /// The expression exactly as it was entered, e.g. `12+3×4`.
  final String expression;

  /// The formatted result, e.g. `24`.
  final String result;

  final DateTime timestamp;

  @override
  List<Object?> get props => <Object?>[expression, result, timestamp];
}
