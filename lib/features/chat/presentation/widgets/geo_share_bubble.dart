import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/geo_share.dart';
import '../screens/geo_share_map_screen.dart';

final DateFormat _arrivalSentTimeFormat = DateFormat.jm();

/// Card for a shared pin, route or arrival message.
class GeoShareBubble extends StatelessWidget {
  const GeoShareBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  static String formatDistance(double meters) => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(1)} km'
      : '${meters.round()} m';

  static String formatDuration(int seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final share = message.geoShare;
    if (share == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Text('Location unavailable'),
      );
    }
    final icon = switch (share.kind) {
      GeoShareKind.pin => Icons.place_rounded,
      GeoShareKind.route => Icons.alt_route_rounded,
      GeoShareKind.arrival => Icons.check_circle_rounded,
    };
    final title = switch (share.kind) {
      GeoShareKind.pin => share.label.isEmpty ? 'Pinned location' : share.label,
      GeoShareKind.route => share.label.isEmpty ? 'Route' : share.label,
      GeoShareKind.arrival =>
        share.label.isEmpty ? 'Arrived' : 'Reached ${share.label}',
    };
    final details = [
      if (share.distanceMeters != null) formatDistance(share.distanceMeters!),
      if (share.durationSeconds != null) formatDuration(share.durationSeconds!),
    ].join(' · ');

    final (containerBg, containerFg) = switch (share.kind) {
      GeoShareKind.pin => (cs.primaryContainer, cs.onPrimaryContainer),
      GeoShareKind.route => (cs.secondaryContainer, cs.onSecondaryContainer),
      GeoShareKind.arrival => (cs.tertiaryContainer, cs.onTertiaryContainer),
    };
    final kindLabel = switch (share.kind) {
      GeoShareKind.pin => 'Location pin',
      GeoShareKind.route => 'Route',
      GeoShareKind.arrival => 'Arrival',
    };

    return Material(
      color: Colors.transparent,
      borderRadius: const BorderRadius.all(AppRadius.bubble),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GeoShareMapScreen(share: share),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 230),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: containerBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: containerFg, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kindLabel.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              details,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                          if (share.kind == GeoShareKind.arrival)
                            Text(
                              'Sent ${_arrivalSentTimeFormat.format(message.sentAt.toLocal())}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => GeoShareMapScreen(share: share),
                          ),
                        ),
                        icon: const Icon(Icons.map_outlined, size: 17),
                        label: const Text('Map'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () => launchUrl(
                          GeoShareMapScreen.directionsUri(share),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.directions_rounded, size: 17),
                        label: const Text('Directions'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
