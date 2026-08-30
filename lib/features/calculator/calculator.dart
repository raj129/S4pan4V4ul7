/// Public surface of the calculator feature module.
///
/// Consumers should import this barrel rather than reaching into the
/// `domain/`, `application/` or `presentation/` folders directly.
library;

export 'application/calculator_cubit.dart';
export 'application/calculator_state.dart';
export 'domain/calculator_engine.dart';
export 'domain/models/angle_unit.dart';
export 'domain/models/calculator_error.dart';
export 'domain/models/eval_result.dart';
export 'domain/models/history_entry.dart';
export 'presentation/calculator_feature.dart';
