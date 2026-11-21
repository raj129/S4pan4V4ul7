import 'package:flutter/material.dart';

/// Data model for a single tile in [ChatAttachmentPanel].
class ChatAttachmentOption {
  const ChatAttachmentOption({
    required this.choice,
    required this.icon,
    required this.label,
    required this.color,
  });

  final String choice;
  final IconData icon;
  final String label;
  final Color color;
}

/// Returns the default ordered attachment options for a chat thread.
List<ChatAttachmentOption> defaultChatAttachmentOptions({
  required bool includeAndroidLocationOptions,
}) {
  return <ChatAttachmentOption>[
    const ChatAttachmentOption(
      choice: 'photo',
      icon: Icons.photo_library_rounded,
      label: 'Gallery',
      color: Color(0xFF7C4DFF),
    ),
    const ChatAttachmentOption(
      choice: 'camera',
      icon: Icons.camera_alt_rounded,
      label: 'Camera',
      color: Color(0xFFE91E63),
    ),
    const ChatAttachmentOption(
      choice: 'vault',
      icon: Icons.lock_rounded,
      label: 'From Vault',
      color: Color(0xFFFF9800),
    ),
    const ChatAttachmentOption(
      choice: 'video',
      icon: Icons.videocam_rounded,
      label: 'Video',
      color: Color(0xFF2196F3),
    ),
    const ChatAttachmentOption(
      choice: 'recordVideo',
      icon: Icons.video_camera_back_rounded,
      label: 'Record Video',
      color: Color(0xFF00A896),
    ),
    const ChatAttachmentOption(
      choice: 'document',
      icon: Icons.insert_drive_file_rounded,
      label: 'Files, GIFs & HDR media',
      color: Color(0xFF009688),
    ),
    const ChatAttachmentOption(
      choice: 'audio',
      icon: Icons.mic_rounded,
      label: 'Audio',
      color: Color(0xFFFF5722),
    ),
    const ChatAttachmentOption(
      choice: 'saved',
      icon: Icons.folder_special_rounded,
      label: 'Saved Files',
      color: Color(0xFF673AB7),
    ),
    const ChatAttachmentOption(
      choice: 'notes',
      icon: Icons.library_books_outlined,
      label: 'Notes & Lists',
      color: Color(0xFF607D8B),
    ),
    if (includeAndroidLocationOptions) ...const [
      ChatAttachmentOption(
        choice: 'liveLocation',
        icon: Icons.location_on_rounded,
        label: 'Live Location',
        color: Color(0xFF4CAF50),
      ),
      ChatAttachmentOption(
        choice: 'pinRoute',
        icon: Icons.pin_drop_rounded,
        label: 'Pin / Route',
        color: Color(0xFFE53935),
      ),
      ChatAttachmentOption(
        choice: 'arrival',
        icon: Icons.notifications_active_rounded,
        label: 'Arrival alert',
        color: Color(0xFF3949AB),
      ),
    ],
  ];
}

/// Inline attachment options drawer rendered below the chat composer.
class ChatAttachmentPanel extends StatelessWidget {
  const ChatAttachmentPanel({
    super.key,
    required this.options,
    required this.onSelect,
  });

  final List<ChatAttachmentOption> options;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 600
                ? (options.length + 1) ~/ 2
                : (options.length + 2) ~/ 3;
            final rows = (options.length + columns - 1) ~/ columns;
            final desiredHeight = (rows * 112 + (rows - 1) * 8).toDouble();
            final gridHeight =
                constraints.maxHeight.isFinite &&
                    constraints.maxHeight < desiredHeight
                ? constraints.maxHeight
                : desiredHeight;
            return SizedBox(
              height: gridHeight,
              child: GridView.builder(
                key: const ValueKey('attachment-options-grid'),
                padding: EdgeInsets.zero,
                physics: gridHeight < desiredHeight
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 112,
                ),
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  return _ChatAttachmentTile(
                    option: option,
                    onTap: () => onSelect(option.choice),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ChatAttachmentTile extends StatelessWidget {
  const _ChatAttachmentTile({required this.option, required this.onTap});

  final ChatAttachmentOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: option.color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(option.icon, color: option.color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              option.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
