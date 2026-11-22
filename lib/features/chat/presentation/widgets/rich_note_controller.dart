import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Inline formatting span over plain-text character offsets `[start, end)`.
class NoteInlineSpan {
  const NoteInlineSpan({
    required this.start,
    required this.end,
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.linkUrl,
  });

  final int start;
  final int end;
  final bool bold;
  final bool italic;
  final bool strikethrough;
  final String? linkUrl;

  bool get isEmpty =>
      start >= end ||
      (!bold && !italic && !strikethrough && linkUrl == null);

  NoteInlineSpan copyWith({
    int? start,
    int? end,
    bool? bold,
    bool? italic,
    bool? strikethrough,
    String? linkUrl,
    bool clearLink = false,
  }) {
    return NoteInlineSpan(
      start: start ?? this.start,
      end: end ?? this.end,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strikethrough: strikethrough ?? this.strikethrough,
      linkUrl: clearLink ? null : (linkUrl ?? this.linkUrl),
    );
  }
}

/// A WYSIWYG [TextEditingController] for notes:
/// - `text` holds clean plain text with zero visible `**`, `*`, `~~`, or
///   `[label](url)` syntax characters.
/// - Inline styles (`bold`, `italic`, `strikethrough`, `linkUrl`) are tracked
///   as character-range spans that shift automatically as the user types.
/// - [toMarkdown] / [fromMarkdown] serialize to and from Markdown-compatible
///   strings so existing `AppNote.content` sync & previews stay compatible.
/// - Automatically continues and renumbers `- ` bullet and `1. ` numbered lists.
class RichNoteTextEditingController extends TextEditingController {
  RichNoteTextEditingController({super.text, List<NoteInlineSpan>? spans})
    : _spans = List<NoteInlineSpan>.from(spans ?? const []),
      _lastTrackedText = text ?? '';

  factory RichNoteTextEditingController.fromMarkdown(String markdown) {
    final parsed = parseMarkdown(markdown);
    return RichNoteTextEditingController(
      text: parsed.plainText,
      spans: parsed.spans,
    );
  }

  List<NoteInlineSpan> _spans;
  String _lastTrackedText;
  final List<TapGestureRecognizer> _recognizers = [];

  bool _pendingBold = false;
  bool _pendingItalic = false;
  bool _pendingStrikethrough = false;
  int? _pendingAtOffset;

  bool get isBoldActive => _isStyleActive((s) => s.bold, _pendingBold);
  bool get isItalicActive => _isStyleActive((s) => s.italic, _pendingItalic);
  bool get isStrikethroughActive =>
      _isStyleActive((s) => s.strikethrough, _pendingStrikethrough);

  List<NoteInlineSpan> get spans => List.unmodifiable(_spans);

  static final RegExp _bulletLineRe = RegExp(r'^(\s*)([-•])\s(.*)$');
  static final RegExp _numberedLineRe = RegExp(r'^(\s*)(\d+)\.\s(.*)$');
  static final RegExp _markdownLinkRe = RegExp(
    r'\[([^\]\n]+)\]\(((?:https?:\/\/|www\.)[^\s)]+)\)',
  );
  static final RegExp _bareUrlRe = RegExp(
    r'(?:https?:\/\/|www\.)[^\s<>()\[\]]+',
  );

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  bool _isStyleActive(
    bool Function(NoteInlineSpan s) predicate,
    bool pendingFlag,
  ) {
    final sel = selection;
    if (!sel.isValid) return pendingFlag;
    if (sel.isCollapsed) {
      final pos = sel.baseOffset;
      if (_pendingAtOffset == pos) {
        return pendingFlag;
      }
      return _spans.any((s) => predicate(s) && pos > s.start && pos <= s.end);
    }
    return _spans.any(
      (s) => predicate(s) && s.start < sel.end && s.end > sel.start,
    );
  }

  /// Replaces text & spans from a Markdown string (e.g., on remote sync).
  void setFromMarkdown(String markdown) {
    final parsed = parseMarkdown(markdown);
    final prevSelection = selection;
    final maxOffset = parsed.plainText.length;
    _spans = parsed.spans;
    _lastTrackedText = parsed.plainText;
    super.value = TextEditingValue(
      text: parsed.plainText,
      selection: prevSelection.isValid
          ? TextSelection(
              baseOffset: prevSelection.baseOffset.clamp(0, maxOffset),
              extentOffset: prevSelection.extentOffset.clamp(0, maxOffset),
            )
          : TextSelection.collapsed(offset: maxOffset),
    );
  }

  /// Call on `TextField.onChanged` so span offsets stay synchronized with
  /// user typing/deletion.
  void syncEditsWithPrevious(String previousText) {
    final nextText = text;
    if (previousText == nextText) {
      _lastTrackedText = nextText;
      return;
    }
    _shiftSpansForDiff(previousText, nextText);
    _lastTrackedText = nextText;
  }

  @override
  set value(TextEditingValue newValue) {
    final prevText = _lastTrackedText;
    final nextText = newValue.text;
    if (prevText != nextText) {
      _shiftSpansForDiff(prevText, nextText);
      _lastTrackedText = nextText;
    }
    super.value = newValue;
  }

  void _shiftSpansForDiff(String oldText, String newText) {
    var prefix = 0;
    final minLen = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    while (prefix < minLen && oldText[prefix] == newText[prefix]) {
      prefix++;
    }

    var oldSuffix = oldText.length;
    var newSuffix = newText.length;
    while (oldSuffix > prefix &&
        newSuffix > prefix &&
        oldText[oldSuffix - 1] == newText[newSuffix - 1]) {
      oldSuffix--;
      newSuffix--;
    }

    final delta = newText.length - oldText.length;
    final insertedLen = newSuffix - prefix;
    final nextSpans = <NoteInlineSpan>[];

    for (final span in _spans) {
      var s = span.start;
      var e = span.end;

      if (e <= prefix) {
        nextSpans.add(span);
      } else if (s >= oldSuffix) {
        s += delta;
        e += delta;
        if (s < e) nextSpans.add(span.copyWith(start: s, end: e));
      } else {
        if (s > prefix) s = prefix;
        if (e < oldSuffix) {
          e = prefix + insertedLen;
        } else {
          e += delta;
        }
        if (s < e) nextSpans.add(span.copyWith(start: s, end: e));
      }
    }

    if (_pendingAtOffset != null && _pendingAtOffset != prefix) {
      _pendingBold = false;
      _pendingItalic = false;
      _pendingStrikethrough = false;
      _pendingAtOffset = null;
    }

    if (insertedLen > 0 &&
        (_pendingBold || _pendingItalic || _pendingStrikethrough)) {
      nextSpans.add(
        NoteInlineSpan(
          start: prefix,
          end: prefix + insertedLen,
          bold: _pendingBold,
          italic: _pendingItalic,
          strikethrough: _pendingStrikethrough,
        ),
      );
    }

    if (_pendingAtOffset != null) {
      _pendingAtOffset = prefix + insertedLen;
    }

    _spans = _normalizeSpans(nextSpans, newText.length);
  }

  /// Toggles bold, italic, or strikethrough on the current selection.
  void toggleStyle({
    bool bold = false,
    bool italic = false,
    bool strikethrough = false,
  }) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) {
      final currentBold = isBoldActive;
      final currentItalic = isItalicActive;
      final currentStrike = isStrikethroughActive;
      _pendingBold = bold ? !currentBold : currentBold;
      _pendingItalic = italic ? !currentItalic : currentItalic;
      _pendingStrikethrough =
          strikethrough ? !currentStrike : currentStrike;
      _pendingAtOffset = sel.isValid ? sel.baseOffset : null;
      notifyListeners();
      return;
    }

    final start = sel.start;
    final end = sel.end;
    final currentlyOn = _spans.any(
      (s) =>
          s.start < end &&
          s.end > start &&
          ((bold && s.bold) ||
              (italic && s.italic) ||
              (strikethrough && s.strikethrough)),
    );

    final updated = <NoteInlineSpan>[];
    for (final s in _spans) {
      if (s.end <= start || s.start >= end) {
        updated.add(s);
        continue;
      }
      if (s.start < start) {
        updated.add(s.copyWith(end: start));
      }
      final midStart = s.start < start ? start : s.start;
      final midEnd = s.end > end ? end : s.end;
      final mid = s.copyWith(
        start: midStart,
        end: midEnd,
        bold: bold ? !currentlyOn : s.bold,
        italic: italic ? !currentlyOn : s.italic,
        strikethrough: strikethrough ? !currentlyOn : s.strikethrough,
      );
      if (!mid.isEmpty) updated.add(mid);
      if (s.end > end) {
        updated.add(s.copyWith(start: end));
      }
    }

    if (!currentlyOn) {
      updated.add(
        NoteInlineSpan(
          start: start,
          end: end,
          bold: bold,
          italic: italic,
          strikethrough: strikethrough,
        ),
      );
    }

    _spans = _normalizeSpans(updated, text.length);
    notifyListeners();
  }

  /// Inserts a clickable hyperlink without showing raw `[label](url)` syntax.
  void insertLink({required String url, String? label}) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return;
    final trimmedLabel = label?.trim() ?? '';
    final sel = selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;

    final display = trimmedLabel.isNotEmpty
        ? trimmedLabel
        : (start != end ? text.substring(start, end).trim() : trimmedUrl);
    final nextText = text.replaceRange(start, end, display);
    _shiftSpansForDiff(text, nextText);
    _lastTrackedText = nextText;
    _spans = _normalizeSpans([
      ..._spans,
      NoteInlineSpan(
        start: start,
        end: start + display.length,
        linkUrl: trimmedUrl,
      ),
    ], nextText.length);

    super.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + display.length),
    );
  }

  /// Toggles `- ` bullet prefix on the line(s) intersecting the selection.
  void toggleBulletList() {
    _transformSelectedLines((lines, startLine, endLine) {
      final allBullets = [
        for (var i = startLine; i <= endLine; i++)
          _bulletLineRe.hasMatch(lines[i]),
      ].every((v) => v);

      for (var i = startLine; i <= endLine; i++) {
        final line = lines[i];
        final bulletMatch = _bulletLineRe.firstMatch(line);
        final numMatch = _numberedLineRe.firstMatch(line);
        if (allBullets) {
          if (bulletMatch != null) {
            lines[i] = '${bulletMatch.group(1)}${bulletMatch.group(3)}';
          }
        } else {
          if (bulletMatch != null) continue;
          if (numMatch != null) {
            lines[i] = '${numMatch.group(1)}- ${numMatch.group(3)}';
          } else {
            lines[i] = '- $line';
          }
        }
      }
      return _renumberLines(lines);
    });
  }

  /// Toggles `1. ` numbered prefix on the line(s) intersecting the selection
  /// and automatically arranges numbers sequentially.
  void toggleNumberedList() {
    _transformSelectedLines((lines, startLine, endLine) {
      final allNumbered = [
        for (var i = startLine; i <= endLine; i++)
          _numberedLineRe.hasMatch(lines[i]),
      ].every((v) => v);

      var counter = 1;
      for (var i = startLine; i <= endLine; i++) {
        final line = lines[i];
        final numMatch = _numberedLineRe.firstMatch(line);
        final bulletMatch = _bulletLineRe.firstMatch(line);
        if (allNumbered) {
          if (numMatch != null) {
            lines[i] = '${numMatch.group(1)}${numMatch.group(3)}';
          }
        } else {
          if (numMatch != null) {
            lines[i] = '${numMatch.group(1)}${counter++}. ${numMatch.group(3)}';
          } else if (bulletMatch != null) {
            lines[i] =
                '${bulletMatch.group(1)}${counter++}. ${bulletMatch.group(3)}';
          } else {
            lines[i] = '${counter++}. $line';
          }
        }
      }
      return _renumberLines(lines);
    });
  }

  /// Handles Enter key continuation and automatic re-numbering of lists.
  bool handleListAutoArrange(TextEditingValue previous, TextEditingValue next) {
    if (next.text.length <= previous.text.length) return false;
    if (!next.selection.isValid || !next.selection.isCollapsed) return false;

    final cursor = next.selection.baseOffset;
    if (cursor <= 0 || next.text[cursor - 1] != '\n') return false;

    final insertedLen = next.text.length - previous.text.length;
    if (insertedLen != 1) return false;

    final lineStartBeforeNewline = next.text.lastIndexOf('\n', cursor - 2) + 1;
    final prevLine = next.text.substring(lineStartBeforeNewline, cursor - 1);

    final bulletMatch = _bulletLineRe.firstMatch(prevLine);
    if (bulletMatch != null) {
      final indent = bulletMatch.group(1) ?? '';
      final marker = bulletMatch.group(2) ?? '-';
      final body = bulletMatch.group(3) ?? '';
      if (body.trim().isEmpty) {
        final updated = next.text.replaceRange(
          lineStartBeforeNewline,
          cursor,
          '\n',
        );
        value = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(
            offset: lineStartBeforeNewline + 1,
          ),
        );
        return true;
      }
      final prefix = '$indent$marker ';
      final updated = next.text.replaceRange(cursor, cursor, prefix);
      value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: cursor + prefix.length),
      );
      return true;
    }

    final numMatch = _numberedLineRe.firstMatch(prevLine);
    if (numMatch != null) {
      final indent = numMatch.group(1) ?? '';
      final currentNum = int.tryParse(numMatch.group(2) ?? '1') ?? 1;
      final body = numMatch.group(3) ?? '';
      if (body.trim().isEmpty) {
        final updated = next.text.replaceRange(
          lineStartBeforeNewline,
          cursor,
          '\n',
        );
        value = _renumberTextPreservingCursor(
          updated,
          lineStartBeforeNewline + 1,
        );
        return true;
      }
      final prefix = '$indent${currentNum + 1}. ';
      final inserted = next.text.replaceRange(cursor, cursor, prefix);
      value = _renumberTextPreservingCursor(inserted, cursor + prefix.length);
      return true;
    }

    return false;
  }

  /// Serializes plain [text] + [_spans] back into Markdown for persistence.
  ///
  /// Splits at newline and list-prefix (`- `, `1. `) boundaries so inline
  /// markers (`**`, `*`, `~~`) never span across lines or break list syntax.
  String toMarkdown() {
    if (_spans.isEmpty || text.isEmpty) return text;
    final boundaries = <int>{0, text.length};
    for (final s in _spans) {
      boundaries.add(s.start.clamp(0, text.length));
      boundaries.add(s.end.clamp(0, text.length));
    }
    var lineOffset = 0;
    for (final line in text.split('\n')) {
      boundaries.add(lineOffset);
      final bm = _bulletLineRe.firstMatch(line);
      if (bm != null) {
        final prefixLen =
            (bm.group(1)?.length ?? 0) + (bm.group(2)?.length ?? 1) + 1;
        boundaries.add((lineOffset + prefixLen).clamp(0, text.length));
      } else {
        final nm = _numberedLineRe.firstMatch(line);
        if (nm != null) {
          final prefixLen =
              (nm.group(1)?.length ?? 0) + (nm.group(2)?.length ?? 1) + 2;
          boundaries.add((lineOffset + prefixLen).clamp(0, text.length));
        }
      }
      final lineEnd = (lineOffset + line.length).clamp(0, text.length);
      boundaries.add(lineEnd);
      if (lineEnd < text.length) {
        boundaries.add(lineEnd + 1);
      }
      lineOffset += line.length + 1;
    }

    final sorted = boundaries.toList()..sort();
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length - 1; i++) {
      final segStart = sorted[i];
      final segEnd = sorted[i + 1];
      if (segStart >= segEnd) continue;
      final segText = text.substring(segStart, segEnd);
      if (segText == '\n' || _isListPrefixSegment(segStart, segEnd)) {
        buf.write(segText);
        continue;
      }

      var bold = false;
      var italic = false;
      var strike = false;
      String? linkUrl;
      for (final s in _spans) {
        if (s.start <= segStart && s.end >= segEnd) {
          bold = bold || s.bold;
          italic = italic || s.italic;
          strike = strike || s.strikethrough;
          linkUrl ??= s.linkUrl;
        }
      }

      var wrapped = segText;
      if (linkUrl != null && linkUrl.isNotEmpty) {
        wrapped = '[$wrapped]($linkUrl)';
      }
      if (strike) wrapped = '~~$wrapped~~';
      if (italic) wrapped = '*$wrapped*';
      if (bold) wrapped = '**$wrapped**';
      buf.write(wrapped);
    }
    return buf.toString();
  }

  bool _isListPrefixSegment(int segStart, int segEnd) {
    final lineStart = segStart == 0 ? 0 : text.lastIndexOf('\n', segStart - 1) + 1;
    if (segStart != lineStart) return false;
    final nextNewline = text.indexOf('\n', lineStart);
    final lineEnd = nextNewline == -1 ? text.length : nextNewline;
    final line = text.substring(lineStart, lineEnd);
    final bm = _bulletLineRe.firstMatch(line);
    if (bm != null) {
      final prefixLen =
          (bm.group(1)?.length ?? 0) + (bm.group(2)?.length ?? 1) + 1;
      return segEnd - segStart == prefixLen;
    }
    final nm = _numberedLineRe.firstMatch(line);
    if (nm != null) {
      final prefixLen =
          (nm.group(1)?.length ?? 0) + (nm.group(2)?.length ?? 1) + 2;
      return segEnd - segStart == prefixLen;
    }
    return false;
  }

  /// Parses Markdown into `(plainText, spans)` without syntax markers.
  static ({String plainText, List<NoteInlineSpan> spans}) parseMarkdown(
    String markdown,
  ) {
    final buf = StringBuffer();
    final spans = <NoteInlineSpan>[];
    final lines = markdown.split('\n');

    for (var i = 0; i < lines.length; i++) {
      _parseInlineMarkdown(lines[i], buf, spans);
      if (i < lines.length - 1) buf.write('\n');
    }

    final plain = buf.toString();
    return (
      plainText: plain,
      spans: _normalizeSpans(spans, plain.length),
    );
  }

  static void _parseInlineMarkdown(
    String line,
    StringBuffer buf,
    List<NoteInlineSpan> spans, {
    bool bold = false,
    bool italic = false,
    bool strikethrough = false,
  }) {
    var i = 0;
    while (i < line.length) {
      // 1. Markdown link: [label](url)
      if (line[i] == '[') {
        final linkMatch = _markdownLinkRe.matchAsPrefix(line, i);
        if (linkMatch != null) {
          final label = linkMatch.group(1)!;
          final url = linkMatch.group(2)!;
          final start = buf.length;
          _parseInlineMarkdown(
            label,
            buf,
            spans,
            bold: bold,
            italic: italic,
            strikethrough: strikethrough,
          );
          if (buf.length > start) {
            spans.add(
              NoteInlineSpan(
                start: start,
                end: buf.length,
                bold: bold,
                italic: italic,
                strikethrough: strikethrough,
                linkUrl: url,
              ),
            );
          }
          i = linkMatch.end;
          continue;
        }
      }

      // 2. Bare URL
      if (line.startsWith('http://', i) ||
          line.startsWith('https://', i) ||
          line.startsWith('www.', i)) {
        final urlMatch = _bareUrlRe.matchAsPrefix(line, i);
        if (urlMatch != null) {
          final url = urlMatch.group(0)!;
          final start = buf.length;
          buf.write(url);
          spans.add(
            NoteInlineSpan(
              start: start,
              end: buf.length,
              bold: bold,
              italic: italic,
              strikethrough: strikethrough,
              linkUrl: url,
            ),
          );
          i = urlMatch.end;
          continue;
        }
      }

      // 3. Inline emphasis & strikethrough delimiters: ***, **, ~~, *
      String? delim;
      var nextBold = bold;
      var nextItalic = italic;
      var nextStrike = strikethrough;

      if (line.startsWith('***', i)) {
        delim = '***';
        nextBold = true;
        nextItalic = true;
      } else if (line.startsWith('**', i)) {
        delim = '**';
        nextBold = true;
      } else if (line.startsWith('~~', i)) {
        delim = '~~';
        nextStrike = true;
      } else if (line[i] == '*') {
        delim = '*';
        nextItalic = true;
      }

      if (delim != null) {
        final closeIdx = _findClosingDelimiter(line, i + delim.length, delim);
        if (closeIdx != -1 && closeIdx > i + delim.length) {
          final inner = line.substring(i + delim.length, closeIdx);
          _parseInlineMarkdown(
            inner,
            buf,
            spans,
            bold: nextBold,
            italic: nextItalic,
            strikethrough: nextStrike,
          );
          i = closeIdx + delim.length;
          continue;
        }
      }

      // 4. Plain character
      final start = buf.length;
      buf.write(line[i]);
      if (bold || italic || strikethrough) {
        spans.add(
          NoteInlineSpan(
            start: start,
            end: buf.length,
            bold: bold,
            italic: italic,
            strikethrough: strikethrough,
          ),
        );
      }
      i++;
    }
  }

  static int _findClosingDelimiter(String line, int from, String delim) {
    if (delim == '*') {
      var idx = from;
      while (idx < line.length) {
        if (line[idx] == '*') {
          // Skip ** pairs when looking for a closing single * unless
          // it's an odd-length run (e.g. *** = * + **).
          var run = 0;
          while (idx + run < line.length && line[idx + run] == '*') {
            run++;
          }
          if (run == 2) {
            idx += 2;
            continue;
          }
          return idx;
        }
        idx++;
      }
      return -1;
    }
    return line.indexOf(delim, from);
  }

  static List<NoteInlineSpan> _normalizeSpans(
    List<NoteInlineSpan> raw,
    int maxLength,
  ) {
    final cleaned = raw
        .map(
          (s) => s.copyWith(
            start: s.start.clamp(0, maxLength),
            end: s.end.clamp(0, maxLength),
          ),
        )
        .where((s) => !s.isEmpty)
        .toList();
    if (cleaned.isEmpty) return const [];

    final boundaries = <int>{};
    for (final s in cleaned) {
      boundaries.add(s.start);
      boundaries.add(s.end);
    }
    final sorted = boundaries.toList()..sort();

    final merged = <NoteInlineSpan>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (a >= b) continue;

      var bold = false;
      var italic = false;
      var strike = false;
      String? linkUrl;
      for (final s in cleaned) {
        if (s.start <= a && s.end >= b) {
          bold = bold || s.bold;
          italic = italic || s.italic;
          strike = strike || s.strikethrough;
          linkUrl ??= s.linkUrl;
        }
      }
      if (!bold && !italic && !strike && linkUrl == null) continue;

      if (merged.isNotEmpty) {
        final prev = merged.last;
        if (prev.end == a &&
            prev.bold == bold &&
            prev.italic == italic &&
            prev.strikethrough == strike &&
            prev.linkUrl == linkUrl) {
          merged[merged.length - 1] = prev.copyWith(end: b);
          continue;
        }
      }
      merged.add(
        NoteInlineSpan(
          start: a,
          end: b,
          bold: bold,
          italic: italic,
          strikethrough: strike,
          linkUrl: linkUrl,
        ),
      );
    }
    return merged;
  }

  void _transformSelectedLines(
    List<String> Function(List<String> lines, int startLine, int endLine)
    transform,
  ) {
    final current = text;
    final sel = selection;
    final start = sel.isValid ? sel.start : current.length;
    final end = sel.isValid ? sel.end : current.length;

    final lines = current.split('\n');
    var charCount = 0;
    var startLine = lines.length - 1;
    var endLine = lines.length - 1;
    var foundStart = false;
    for (var i = 0; i < lines.length; i++) {
      final lineEnd = charCount + lines[i].length;
      if (!foundStart && start <= lineEnd) {
        startLine = i;
        foundStart = true;
      }
      if (end <= lineEnd) {
        endLine = i;
        break;
      }
      charCount = lineEnd + 1;
    }

    final updatedLines = transform(lines, startLine, endLine);
    final updatedText = updatedLines.join('\n');
    value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(
        offset: end.clamp(0, updatedText.length),
      ),
    );
  }

  static List<String> _renumberLines(List<String> lines) {
    final counters = <String, int>{};
    final result = List<String>.from(lines);
    for (var i = 0; i < result.length; i++) {
      final m = _numberedLineRe.firstMatch(result[i]);
      if (m == null) {
        counters.clear();
        continue;
      }
      final indent = m.group(1) ?? '';
      final body = m.group(3) ?? '';
      final nextNum = (counters[indent] ?? 0) + 1;
      counters[indent] = nextNum;
      result[i] = '$indent$nextNum. $body';
    }
    return result;
  }

  static TextEditingValue _renumberTextPreservingCursor(
    String raw,
    int desiredCursor,
  ) {
    final lines = raw.split('\n');
    final renumbered = _renumberLines(lines).join('\n');
    return TextEditingValue(
      text: renumbered,
      selection: TextSelection.collapsed(
        offset: desiredCursor.clamp(0, renumbered.length),
      ),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final baseStyle = style ?? theme.textTheme.bodyLarge ?? const TextStyle();

    if (text.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    final activeSpans = <NoteInlineSpan>[..._spans];
    for (final m in _bareUrlRe.allMatches(text)) {
      final alreadyLinked = activeSpans.any(
        (s) => s.linkUrl != null && s.start <= m.start && s.end >= m.end,
      );
      if (!alreadyLinked) {
        activeSpans.add(
          NoteInlineSpan(start: m.start, end: m.end, linkUrl: m.group(0)),
        );
      }
    }

    final boundaries = <int>{0, text.length};
    for (final s in activeSpans) {
      boundaries.add(s.start.clamp(0, text.length));
      boundaries.add(s.end.clamp(0, text.length));
    }

    final sorted = boundaries.toList()..sort();
    final children = <InlineSpan>[];

    for (var i = 0; i < sorted.length - 1; i++) {
      final segStart = sorted[i];
      final segEnd = sorted[i + 1];
      if (segStart >= segEnd) continue;

      var segStyle = baseStyle;
      var bold = false;
      var italic = false;
      var strike = false;
      String? linkUrl;

      for (final s in activeSpans) {
        if (s.start <= segStart && s.end >= segEnd) {
          bold = bold || s.bold;
          italic = italic || s.italic;
          strike = strike || s.strikethrough;
          linkUrl ??= s.linkUrl;
        }
      }

      final decorations = <TextDecoration>[
        if (strike) TextDecoration.lineThrough,
        if (linkUrl != null) TextDecoration.underline,
      ];

      TapGestureRecognizer? recognizer;
      if (linkUrl != null) {
        final targetUrl = linkUrl;
        recognizer = TapGestureRecognizer()
          ..onTap = () => unawaited(openNoteUrl(targetUrl));
        _recognizers.add(recognizer);
      }

      segStyle = segStyle.copyWith(
        fontWeight: bold ? FontWeight.w700 : null,
        fontStyle: italic ? FontStyle.italic : null,
        color: linkUrl != null ? cs.primary : null,
        decoration: decorations.isEmpty
            ? null
            : TextDecoration.combine(decorations),
        decorationColor: linkUrl != null ? cs.primary : null,
      );

      children.add(
        TextSpan(
          text: text.substring(segStart, segEnd),
          style: segStyle,
          recognizer: recognizer,
        ),
      );
    }

    return TextSpan(style: baseStyle, children: children);
  }

  /// Extracts all URLs from both explicit link spans and bare URLs in [text].
  List<String> extractActiveUrls() {
    final urls = <String>{};
    for (final s in _spans) {
      if (s.linkUrl != null && s.linkUrl!.isNotEmpty) {
        urls.add(s.linkUrl!);
      }
    }
    for (final m in _bareUrlRe.allMatches(text)) {
      urls.add(m.group(0)!);
    }
    return urls.toList(growable: false);
  }

  /// Extracts all URLs from a raw Markdown string.
  static List<String> extractUrls(String raw) {
    final parsed = parseMarkdown(raw);
    final urls = <String>{};
    for (final s in parsed.spans) {
      if (s.linkUrl != null && s.linkUrl!.isNotEmpty) {
        urls.add(s.linkUrl!);
      }
    }
    for (final m in _bareUrlRe.allMatches(parsed.plainText)) {
      urls.add(m.group(0)!);
    }
    return urls.toList(growable: false);
  }

  /// Launches a URL in an external browser safely.
  static Future<void> openNoteUrl(String rawUrl) async {
    final normalized =
        rawUrl.startsWith('http://') || rawUrl.startsWith('https://')
        ? rawUrl
        : 'https://$rawUrl';
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Renders read-only formatted rich text (for `SharedNoteBubble` / previews).
  static Widget buildReadOnlyRichText(
    BuildContext context, {
    required String text,
    TextStyle? style,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    return _ReadOnlyRichNoteText(
      text: text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

class _ReadOnlyRichNoteText extends StatefulWidget {
  const _ReadOnlyRichNoteText({
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<_ReadOnlyRichNoteText> createState() => _ReadOnlyRichNoteTextState();
}

class _ReadOnlyRichNoteTextState extends State<_ReadOnlyRichNoteText> {
  late RichNoteTextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = RichNoteTextEditingController.fromMarkdown(widget.text);
  }

  @override
  void didUpdateWidget(covariant _ReadOnlyRichNoteText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _ctrl.setFromMarkdown(widget.text);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final span = _ctrl.buildTextSpan(
      context: context,
      style: widget.style,
      withComposing: false,
    );
    return Text.rich(
      span,
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }
}
