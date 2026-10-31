import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/geo_share.dart';
import '../screens/geo_share_map_screen.dart';

/// Card for a shared pin, route or arrival message.
class GeoShareBubble extends StatelessWidget {
  const GeoShareBubble({super.key, required this.message, required this.isMine});

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
      if (share.durationSeconds != null)
        formatDuration(share.durationSeconds!),
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GeoShareMapScreen(share: share),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onPrimaryContainer,
                      child: Icon(icon),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (details.isNotEmpty) Text(details),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GeoShareMapScreen(share: share),
                        ),
                      ),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('Map'),
                    ),
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        GeoShareMapScreen.directionsUri(share),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.directions_rounded, size: 18),
                      label: const Text('Directions'),
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
