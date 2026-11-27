import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Files or text/links shared into the app from another app (gallery, camera,
/// YouTube, Chrome, etc.) that the user chose to send in a chat.
///
/// The chat list shows a "choose a chat" banner while [hasPending] is true and
/// the opened thread consumes the files or text with [take] / [takeText].
class ChatShareInbox extends ChangeNotifier {
  ChatShareInbox._();

  static final ChatShareInbox instance = ChatShareInbox._();

  List<XFile> _files = const [];
  String? _text;

  bool get hasPending => _files.isNotEmpty || hasPendingText;
  bool get hasPendingText => _text != null && _text!.trim().isNotEmpty;
  String? get pendingText => _text;
  int get count => _files.length;

  void set(List<XFile> files) {
    _files = List<XFile>.unmodifiable(files);
    _text = null;
    notifyListeners();
  }

  void setText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _files = const [];
    _text = trimmed;
    notifyListeners();
  }

  List<XFile> take() {
    final files = _files;
    if (files.isEmpty) return const [];
    _files = const [];
    notifyListeners();
    return files;
  }

  String? takeText() {
    final text = _text;
    if (text == null || text.isEmpty) return null;
    _text = null;
    notifyListeners();
    return text;
  }

  void clear() {
    if (_files.isEmpty && _text == null) return;
    _files = const [];
    _text = null;
    notifyListeners();
  }
}
