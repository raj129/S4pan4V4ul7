import 'models/calculator_error.dart';
import 'models/token.dart';

/// Converts infix [Token]s into Reverse Polish Notation using the
/// shunting-yard algorithm.
///
/// Unclosed parentheses are auto-balanced, which lets the UI show a live
/// preview while the user is still typing `sin(30`.
class Parser {
  const Parser();

  List<Token> toRpn(List<Token> tokens) {
    final output = <Token>[];
    final stack = <Token>[];

    for (final token in tokens) {
      switch (token.type) {
        case TokenType.number:
        case TokenType.constant:
          output.add(token);
        case TokenType.postfix:
          output.add(token);
        case TokenType.function:
          stack.add(token);
        case TokenType.unaryMinus:
          // Prefix negation is right-associative, so it always stacks.
          stack.add(token);
        case TokenType.operator:
          final spec = kOperators[token.text];
          if (spec == null) throw const CalculatorError.syntax();
          while (stack.isNotEmpty && _shouldPopBefore(stack.last, spec)) {
            output.add(stack.removeLast());
          }
          stack.add(token);
        case TokenType.leftParen:
          stack.add(token);
        case TokenType.rightParen:
          var matched = false;
          while (stack.isNotEmpty) {
            final top = stack.removeLast();
            if (top.type == TokenType.leftParen) {
              matched = true;
              break;
            }
            output.add(top);
          }
          if (!matched) throw const CalculatorError.syntax();
          if (stack.isNotEmpty && stack.last.type == TokenType.function) {
            output.add(stack.removeLast());
          }
      }
    }

    while (stack.isNotEmpty) {
      final top = stack.removeLast();
      // Auto-balance: a dangling `(` is treated as if closed at the end.
      if (top.type == TokenType.leftParen) continue;
      output.add(top);
    }

    return output;
  }

  bool _shouldPopBefore(Token top, OperatorSpec incoming) {
    if (top.type == TokenType.leftParen) return false;
    if (top.type == TokenType.function) return true;
    if (top.type == TokenType.unaryMinus) {
      return kUnaryMinusPrecedence > incoming.precedence ||
          (kUnaryMinusPrecedence == incoming.precedence &&
              !incoming.rightAssociative);
    }
    if (top.type != TokenType.operator) return false;
    final topSpec = kOperators[top.text];
    if (topSpec == null) return false;
    if (incoming.rightAssociative) {
      return topSpec.precedence > incoming.precedence;
    }
    return topSpec.precedence >= incoming.precedence;
  }
}
