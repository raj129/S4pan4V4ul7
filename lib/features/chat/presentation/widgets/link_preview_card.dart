import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/services/link_preview_service.dart';

/// Compact rich preview card for a URL in a chat bubble or composer.
class LinkPreviewCard extends StatefulWidget {
  const LinkPreviewCard({
    super.key,
    required this.url,
    this.compact = false,
    this.onDismiss,
  });

  final String url;
  final bool compact;
  final VoidCallback? onDismiss;

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  LinkPreviewData? _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  void _load() {
    final cached = LinkPreviewService.instance.peek(widget.url);
    if (cached != null) {
      _data = cached;
      _loading = false;
      return;
    }
    _data = null;
    _loading = true;
    LinkPreviewService.instance.fetch(widget.url).then((result) {
      if (!mounted) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final data = _data;

    if (data == null && !_loading && widget.onDismiss == null) {
      return const SizedBox.shrink();
    }

    final uri = Uri.tryParse(widget.url);
    final domain =
        data?.siteName ??
        data?.domain ??
        (uri?.host.replaceFirst(RegExp(r'^www\.'), '') ?? 'Link');

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: cs.primary, width: 3)),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (data?.imageUrl != null && data!.imageUrl!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: data.imageUrl!,
                    width: widget.compact ? 48 : 64,
                    height: widget.compact ? 48 : 64,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 10),
              ] else if (_loading) ...[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 10),
              ] else ...[
                Icon(Icons.link_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      domain,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (data?.title != null && data!.title!.isNotEmpty)
                      Text(
                        data.title!,
                        maxLines: widget.compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      )
                    else
                      Text(
                        widget.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    if (!widget.compact &&
                        data?.description != null &&
                        data!.description!.isNotEmpty)
                      Text(
                        data.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.onDismiss != null)
                IconButton(
                  tooltip: 'Dismiss preview',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onDismiss,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
