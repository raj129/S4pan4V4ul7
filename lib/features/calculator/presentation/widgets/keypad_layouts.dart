import '../../domain/models/angle_unit.dart';
import 'calc_button.dart';

/// What pressing a key does.
enum CalcAction {
  input,
  smartParen,
  equals,
  clear,
  backspace,
  toggleAngleUnit,
  toggleInverse,
  memoryClear,
  memoryRecall,
  memoryAdd,
  memorySubtract,
}

/// Declarative description of a single key.
class CalcKey {
  const CalcKey({
    required this.id,
    required this.label,
    required this.action,
    this.payload,
    this.style = CalcKeyStyle.digit,
    this.flex = 1,
  });

  /// Stable identity used by tests and by the vault trigger detector.
  final String id;

  final String label;
  final CalcAction action;

  /// Text inserted into the expression for [CalcAction.input].
  final String? payload;

  final CalcKeyStyle style;
  final int flex;
}

/// Key identifiers that participate in the hidden vault trigger.
const String kSevenKeyId = 'digit-7';
const String kEqualsKeyId = 'equals';

/// The always-visible 4-column keypad.
List<List<CalcKey>> basicKeypadRows() {
  return <List<CalcKey>>[
    <CalcKey>[
      const CalcKey(
        id: 'clear',
        label: 'AC',
        action: CalcAction.clear,
        style: CalcKeyStyle.destructive,
      ),
      const CalcKey(
        id: 'percent',
        label: '%',
        action: CalcAction.input,
        payload: '%',
        style: CalcKeyStyle.function,
      ),
      const CalcKey(
        id: 'paren',
        label: '( )',
        action: CalcAction.smartParen,
        style: CalcKeyStyle.function,
      ),
      const CalcKey(
        id: 'divide',
        label: '÷',
        action: CalcAction.input,
        payload: '÷',
        style: CalcKeyStyle.operator,
      ),
    ],
    <CalcKey>[
      _digit('7'),
      _digit('8'),
      _digit('9'),
      const CalcKey(
        id: 'multiply',
        label: '×',
        action: CalcAction.input,
        payload: '×',
        style: CalcKeyStyle.operator,
      ),
    ],
    <CalcKey>[
      _digit('4'),
      _digit('5'),
      _digit('6'),
      const CalcKey(
        id: 'subtract',
        label: '−',
        action: CalcAction.input,
        payload: '-',
        style: CalcKeyStyle.operator,
      ),
    ],
    <CalcKey>[
      _digit('1'),
      _digit('2'),
      _digit('3'),
      const CalcKey(
        id: 'add',
        label: '+',
        action: CalcAction.input,
        payload: '+',
        style: CalcKeyStyle.operator,
      ),
    ],
    <CalcKey>[
      const CalcKey(
        id: 'decimal',
        label: '.',
        action: CalcAction.input,
        payload: '.',
      ),
      _digit('0'),
      const CalcKey(
        id: 'backspace',
        label: '⌫',
        action: CalcAction.backspace,
        style: CalcKeyStyle.function,
      ),
      const CalcKey(
        id: kEqualsKeyId,
        label: '=',
        action: CalcAction.equals,
        style: CalcKeyStyle.operator,
      ),
    ],
  ];
}

/// The collapsible 5-column scientific rows.
///
/// [inverseMode] swaps each key for its second function.
List<List<CalcKey>> scientificKeypadRows({
  required bool inverseMode,
  required AngleUnit angleUnit,
}) {
  return <List<CalcKey>>[
    <CalcKey>[
      CalcKey(
        id: 'inverse',
        label: 'INV',
        action: CalcAction.toggleInverse,
        style: inverseMode ? CalcKeyStyle.accent : CalcKeyStyle.function,
      ),
      CalcKey(
        id: 'angle-unit',
        label: angleUnit.label,
        action: CalcAction.toggleAngleUnit,
        style: CalcKeyStyle.function,
      ),
      _function(
        id: 'sin',
        label: inverseMode ? 'sin⁻¹' : 'sin',
        payload: inverseMode ? 'asin(' : 'sin(',
      ),
      _function(
        id: 'cos',
        label: inverseMode ? 'cos⁻¹' : 'cos',
        payload: inverseMode ? 'acos(' : 'cos(',
      ),
      _function(
        id: 'tan',
        label: inverseMode ? 'tan⁻¹' : 'tan',
        payload: inverseMode ? 'atan(' : 'tan(',
      ),
    ],
    <CalcKey>[
      _function(
        id: 'root',
        label: inverseMode ? '∛' : '√',
        payload: inverseMode ? '∛(' : '√(',
      ),
      _function(
        id: 'ln',
        label: inverseMode ? 'eˣ' : 'ln',
        payload: inverseMode ? 'exp(' : 'ln(',
      ),
      _function(
        id: 'log',
        label: inverseMode ? '10ˣ' : 'log',
        payload: inverseMode ? '10^' : 'log(',
      ),
      _function(id: 'power', label: 'xʸ', payload: '^'),
      _function(id: 'factorial', label: 'x!', payload: '!'),
    ],
    <CalcKey>[
      _function(id: 'pi', label: 'π', payload: 'π'),
      _function(id: 'euler', label: 'e', payload: 'e'),
      _function(id: 'exp', label: 'EXP', payload: 'E'),
      _function(id: 'mod', label: 'mod', payload: 'mod'),
      _function(id: 'abs', label: '|x|', payload: 'abs('),
    ],
  ];
}

CalcKey _digit(String digit) => CalcKey(
  id: 'digit-$digit',
  label: digit,
  action: CalcAction.input,
  payload: digit,
);

CalcKey _function({
  required String id,
  required String label,
  required String payload,
}) => CalcKey(
  id: id,
  label: label,
  action: CalcAction.input,
  payload: payload,
  style: CalcKeyStyle.function,
);
