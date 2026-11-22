import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:photo_vault/core/location/maps/google_api_auth.dart';
import 'package:photo_vault/core/presentation/theme/app_colors.dart';
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
    this.onRefreshLiveLocation,
    this.onRequestLiveLocationRefresh,
  });

  final ChatMessage message;
  final bool isMine;
  final LiveLocationRepository? repository;
  final String? sessionId;
  final Future<void> Function()? onStopSharing;
  final Future<void> Function()? onRefreshLiveLocation;
  final Future<void> Function()? onRequestLiveLocationRefresh;

  @override
  State<LiveLocationBubble> createState() => _LiveLocationBubbleState();
}

class _LiveLocationBubbleState extends State<LiveLocationBubble> {
  Stream<LiveLocationSession?>? _sessionStream;
  Timer? _stalenessTimer;
  Timer? _refreshCooldownTimer;
  bool _refreshPending = false;
  String? _apiKey;
  Map<String, String> _identityHeaders = const {};

  @override
  void initState() {
    super.initState();
    _createSessionStream();
    _stalenessTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    if (Platform.isAndroid) {
      unawaited(_loadStaticMapAuth());
    }
  }

  Future<void> _loadStaticMapAuth() async {
    final key = await GoogleApiAuth.instance.key;
    final headers = await GoogleApiAuth.instance.identityHeaders();
    if (!mounted || key.isEmpty) return;
    setState(() {
      _apiKey = key;
      _identityHeaders = headers;
    });
  }

  @override
  void dispose() {
    _stalenessTimer?.cancel();
    _refreshCooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLocation({
    required Future<void> Function()? action,
    required String successMessage,
  }) async {
    if (action == null || _refreshPending) return;
    setState(() => _refreshPending = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      _refreshCooldownTimer?.cancel();
      _refreshCooldownTimer = Timer(const Duration(seconds: 20), () {
        if (mounted) setState(() => _refreshPending = false);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _refreshPending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh location: $error')),
        );
      }
    }
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
        final timestampFormat = DateFormat.yMMMd().add_jm();
        final startedAtText = session == null
            ? null
            : timestampFormat.format(session.startedAt.toLocal());
        final stoppedAt = session == null
            ? null
            : session.stoppedAt ??
                  (session.isExpired
                      ? session.expiresAt
                      : !session.isActive
                      ? session.lastUpdatedAt
                      : null);
        final stoppedAtText = stoppedAt == null
            ? null
            : timestampFormat.format(stoppedAt.toLocal());
        final stoppedLabel =
            session?.isExpired == true && session?.isActive == true
            ? 'Ended'
            : 'Stopped';

        return Material(
          color: Colors.transparent,
          borderRadius: const BorderRadius.all(AppRadius.bubble),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap:
                (sessionUnavailable && !isWaiting) ||
                    (!isActive && !hasPoint && !isWaiting)
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
                        onRefreshLiveLocation: widget.onRefreshLiveLocation,
                        onRequestLiveLocationRefresh:
                            widget.onRequestLiveLocationRefresh,
                      ),
                    ),
                  ),
            child: Container(
              width: 256,
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 128,
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildMapPreview(
                            context: context,
                            point: session?.currentPoint,
                            isLive: isLive,
                            statusText: statusText,
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Theme.of(
                                    context,
                                  ).colorScheme.surface.withValues(alpha: 0.78),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 8,
                            child: Text(
                              isLive
                                  ? 'Tap to view live map'
                                  : hasPoint
                                  ? 'View last known location'
                                  : 'View location',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
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
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(
                        Icons.near_me_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                if (isActive &&
                    isStale &&
                    (widget.isMine
                        ? widget.onRefreshLiveLocation != null
                        : widget.onRequestLiveLocationRefresh != null)) ...[
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _refreshPending
                          ? null
                          : () => _refreshLocation(
                              action: widget.isMine
                                  ? widget.onRefreshLiveLocation
                                  : widget.onRequestLiveLocationRefresh,
                              successMessage: widget.isMine
                                  ? 'Refreshing your location…'
                                  : 'Refresh requested. The location will update when the sharer’s device is available.',
                            ),
                      icon: _refreshPending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 16),
                      label: Text(
                        _refreshPending
                            ? 'Refresh requested'
                            : widget.isMine
                            ? 'Refresh Location'
                            : 'Request Refresh',
                      ),
                    ),
                  ),
                ],
                if (startedAtText != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Started $startedAtText',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (stoppedAtText != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '$stoppedLabel $stoppedAtText',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
        ),
        );
      },
    );
  }

  Widget _buildMapPreview({
    required BuildContext context,
    required LiveLocationPoint? point,
    required bool isLive,
    required String statusText,
  }) {
    final fallback = _MapFallbackCard(
      point: point,
      isLive: isLive,
      statusText: statusText,
    );
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty || point == null) {
      return fallback;
    }

    // Round to 4 decimals (~11 m) so minor GPS jitter reuses the cached tile.
    final roundedLat = point.latitude.toStringAsFixed(4);
    final roundedLng = point.longitude.toStringAsFixed(4);
    final staticMapUrl =
        'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$roundedLat,$roundedLng'
        '&zoom=15'
        '&size=512x256'
        '&scale=2'
        '&markers=color:red|$roundedLat,$roundedLng'
        '&key=${Uri.encodeQueryComponent(apiKey)}';
    final cacheKey = 'static_map_${roundedLat}_$roundedLng';

    return CachedNetworkImage(
      imageUrl: staticMapUrl,
      httpHeaders: _identityHeaders,
      cacheKey: cacheKey,
      fit: BoxFit.cover,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
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

class _MapFallbackCard extends StatelessWidget {
  const _MapFallbackCard({
    required this.point,
    required this.isLive,
    required this.statusText,
  });

  final LiveLocationPoint? point;
  final bool isLive;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = point != null
        ? '${point!.latitude.toStringAsFixed(4)}, ${point!.longitude.toStringAsFixed(4)}'
        : statusText;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surfaceContainerHigh,
            colorScheme.primaryContainer.withValues(alpha: 0.35),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _MapGridPainter(
          lineColor: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20, left: 10, right: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isLive
                      ? context.semantic.online.withValues(alpha: 0.16)
                      : colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isLive
                      ? Icons.my_location_rounded
                      : Icons.location_on_outlined,
                  color: isLive
                      ? context.semantic.online
                      : colorScheme.onPrimaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  const _MapGridPainter({required this.lineColor});

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    const step = 24.0;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MapGridPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor;
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
