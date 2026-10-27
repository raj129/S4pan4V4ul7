import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/live_location.dart';
import '../../domain/repositories/live_location_repository.dart';
import '../screens/live_location_map_screen.dart';

/// Chat card for a live-location session. Session updates come from Firestore.
class LiveLocationBubble extends StatefulWidget {
  const LiveLocationBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.repository,
    required this.sessionId,
    this.onStopSharing,
  });

  final ChatMessage message;
  final bool isMine;
  final LiveLocationRepository? repository;
  final String? sessionId;
  final Future<void> Function()? onStopSharing;

  @override
  State<LiveLocationBubble> createState() => _LiveLocationBubbleState();
}

class _LiveLocationBubbleState extends State<LiveLocationBubble> {
  Stream<LiveLocationSession?>? _sessionStream;
  Timer? _stalenessTimer;

  @override
  void initState() {
    super.initState();
    _createSessionStream();
    _stalenessTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stalenessTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LiveLocationBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.message.threadId != widget.message.threadId ||
        oldWidget.message.senderId != widget.message.senderId ||
        oldWidget.sessionId != widget.sessionId) {
      _createSessionStream();
    }
  }

  void _createSessionStream() {
    final repository = widget.repository;
    final sessionId = widget.sessionId;
    _sessionStream = repository == null || sessionId == null
        ? null
        : repository.watchUserSession(
            sessionId: sessionId,
            threadId: widget.message.threadId,
            userId: widget.message.senderId,
          );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const _LocationUnavailableCard(
        label: 'Live location is available on Android.',
      );
    }

    final sessionStream = _sessionStream;
    if (sessionStream == null) {
      return const _LocationUnavailableCard(
        label: 'Live location is currently unavailable.',
      );
    }

    return StreamBuilder<LiveLocationSession?>(
      stream: sessionStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _LocationUnavailableCard(
            label: 'Could not load this live location.',
          );
        }
        final session = snapshot.data;
        final isLive = session?.isLive ?? false;
        final isStale = session?.isStale ?? false;
        final isActive =
            session?.isActive == true && session?.isExpired == false;
        final sessionUnavailable = session == null;
        final isWaiting =
            sessionUnavailable &&
            snapshot.connectionState == ConnectionState.waiting;
        final hasPoint = session?.currentPoint != null;
        final statusText = sessionUnavailable
            ? isWaiting
                  ? 'Connecting to location…'
                  : 'Live location ended'
            : isActive
            ? isStale
                  ? 'Signal paused'
                  : 'Live until ${DateFormat.jm().format(session.expiresAt.toLocal())}'
            : session.isExpired
            ? 'Live location ended'
            : 'Sharing stopped';

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: sessionUnavailable || (!isActive && !hasPoint)
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LiveLocationMapScreen(
                      threadId: widget.message.threadId,
                      userId: widget.message.senderId,
                      isMine: widget.isMine,
                      initialSession: session,
                      sessionStream: sessionStream,
                      onStopSharing: widget.onStopSharing,
                    ),
                  ),
                ),
          child: Container(
            width: 250,
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 110,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 56,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isLive
                                ? Icons.my_location
                                : Icons.location_on_outlined,
                            color: isLive ? Colors.green : null,
                            size: 30,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isLive
                                ? 'Tap to view live map'
                                : hasPoint
                                ? 'View last known location'
                                : 'View location',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      if (isActive)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _LivePill(isStale: isStale),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    const Icon(Icons.near_me_outlined, size: 16),
                    const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                if (widget.isMine &&
                    isActive &&
                    widget.onStopSharing != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await widget.onStopSharing!();
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Could not stop sharing: $error'),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.stop_circle_outlined, size: 16),
                      label: const Text('Stop Sharing'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.isStale});

  final bool isStale;

  @override
  Widget build(BuildContext context) {
    final color = isStale ? Colors.amber.shade800 : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        isStale ? 'PAUSED' : 'LIVE',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _LocationUnavailableCard extends StatelessWidget {
  const _LocationUnavailableCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 250,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      leading: const Icon(Icons.location_disabled_outlined),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
    ),
  );
}
