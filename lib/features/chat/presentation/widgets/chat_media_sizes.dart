/// Layout sizes for media rendered inside chat bubbles.
abstract final class ChatMediaSizes {
  /// Width reserved for photos and GIFs.
  static const double mediaWidth = 220;
  static const double mediaMinHeight = 80;
  static const double mediaMaxHeight = 320;

  /// Stickers render at ~60% of the photo tile so they don't dominate a chat.
  static const double sticker = 132;

  /// Emoji-only messages ("big emoji").
  static const double emoji = 36;
  static const double emojiFontSize = 33;
}
