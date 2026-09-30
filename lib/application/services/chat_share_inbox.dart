import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Files shared into the app from another app (gallery, camera) that the user
/// chose to send in a chat rather than import into the vault.
///
/// The chat list shows a "choose a chat" banner while [hasPending] is true and
/// the opened thread consumes the files with [take].
class ChatShareInbox extends ChangeNotifier {
  ChatShareInbox._();

  static final ChatShareInbox instance = ChatShareInbox._();

  List<XFile> _files = const [];

  bool get hasPending => _files.isNotEmpty;
  int get count => _files.length;

  void set(List<XFile> files) {
    _files = List<XFile>.unmodifiable(files);
    notifyListeners();
  }

  List<XFile> take() {
    final files = _files;
    if (files.isEmpty) return const [];
    _files = const [];
    notifyListeners();
    return files;
  }

  void clear() {
    if (_files.isEmpty) return;
    _files = const [];
    notifyListeners();
  }
}
