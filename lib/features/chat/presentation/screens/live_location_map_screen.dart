import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/live_location.dart';

const _googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_ANDROID_API_KEY');

class LiveLocationMapScreen extends StatefulWidget {
  const LiveLocationMapScreen({
    super.key,
    required this.threadId,
    required this.userId,
    required this.isMine,
    required this.sessionStream,
    this.initialSession,
    this.onStopSharing,
  });

  final String threadId;
  final String userId;
  final bool isMine;
  final Stream<LiveLocationSession?> sessionStream;
  final LiveLocationSession? initialSession;
  final Future<void> Function()? onStopSharing;

  @override
  State<LiveLocationMapScreen> createState() => _LiveLocationMapScreenState();
}

class _LiveLocationMapScreenState extends State<LiveLocationMapScreen> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const Scaffold(
        body: Center(child: Text('Live location is available on Android.')),
      );
    }
    return StreamBuilder<LiveLocationSession?>(
      stream: widget.sessionStream,
      initialData: widget.initialSession,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Live location')),
            body: const Center(
              child: Text('Could not receive live location updates.'),
            ),
          );
        }
        return _buildSession(context, snapshot.data);
      },
    );
  }

  Widget _buildSession(BuildContext context, LiveLocationSession? session) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final point = session?.isActive == true && session?.isExpired == false
        ? session?.currentPoint
        : null;
    final isLive = session?.isLive ?? false;
    final isStale = session?.isStale ?? false;
    final isActive = session?.isActive == true && session?.isExpired == false;
    final mapConfigured = _googleMapsApiKey.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.isMine ? 'Your Live Location' : 'Live Location'),
            Text(
              _statusLabel(session, isActive, isLive, isStale),
              style: theme.textTheme.labelSmall?.copyWith(
                color: isLive ? (isStale ? Colors.amber : Colors.green) : null,
              ),
            ),
          ],
        ),
        actions: [
          if (widget.isMine && isActive && widget.onStopSharing != null)
            TextButton.icon(
              onPressed: () async {
                try {
                  await widget.onStopSharing!();
                  if (context.mounted) Navigator.of(context).pop();
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not stop sharing: $error')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
              label: const Text('Stop', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: !mapConfigured
                ? const _MapUnavailable(
                    message:
                        'Google Maps is not configured. Set the Android Maps '
                        'API key in the app build environment.',
                  )
                : point == null
                ? const _MapUnavailable(
                    message: 'Waiting for the sender’s first location…',
                  )
                : _LiveGoogleMap(point: point),
          ),
          if (session != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: _LocationDetailsCard(
                session: session,
                isLive: isLive,
                isStale: isStale,
                point: point,
              ),
            ),
        ],
      ),
      backgroundColor: colors.surface,
    );
  }

  String _statusLabel(
    LiveLocationSession? session,
    bool isActive,
    bool isLive,
    bool isStale,
  ) {
    if (session == null) return 'Location session ended';
    if (isActive && isStale) return 'Signal paused';
    if (isLive) {
      final remaining = session.expiresAt.difference(DateTime.now());
      if (remaining.isNegative) return 'Expired';
      if (remaining.inHours > 0) {
        return '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m remaining';
      }
      return '${remaining.inMinutes}m ${remaining.inSeconds.remainder(60)}s remaining';
    }
    return session.isExpired ? 'Session expired' : 'Sharing stopped';
  }
}

class _LiveGoogleMap extends StatefulWidget {
  const _LiveGoogleMap({required this.point});

  final LiveLocationPoint point;

  @override
  State<_LiveGoogleMap> createState() => _LiveGoogleMapState();
}

class _LiveGoogleMapState extends State<_LiveGoogleMap> {
  GoogleMapController? _controller;

  @override
  void didUpdateWidget(covariant _LiveGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point.latitude != widget.point.latitude ||
        oldWidget.point.longitude != widget.point.longitude) {
      _controller?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(widget.point.latitude, widget.point.longitude),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.point;
    final center = LatLng(point.latitude, point.longitude);
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: center, zoom: 16),
      onMapCreated: (controller) => _controller = controller,
      markers: {
        Marker(
          markerId: const MarkerId('shared-location'),
          position: center,
          rotation: point.heading ?? 0,
          infoWindow: const InfoWindow(title: 'Shared location'),
        ),
      },
      circles: {
        Circle(
          circleId: const CircleId('location-accuracy'),
          center: center,
          radius: math.max(point.accuracy, 5.0),
          fillColor: Colors.blue.withValues(alpha: 0.12),
          strokeColor: Colors.blue.withValues(alpha: 0.5),
          strokeWidth: 1,
        ),
      },
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }
}

class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _LocationDetailsCard extends StatelessWidget {
  const _LocationDetailsCard({
    required this.session,
    required this.isLive,
    required this.isStale,
    required this.point,
  });

  final LiveLocationSession session;
  final bool isLive;
  final bool isStale;
  final LiveLocationPoint? point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final currentPoint = point;
    return Card(
      elevation: 5,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.radar,
                  color: isLive ? Colors.green : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isStale
                        ? 'Signal paused'
                        : isLive
                        ? 'Live tracking active'
                        : 'Location session ended',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  DateFormat.jm().format(session.lastUpdatedAt.toLocal()),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
            const Divider(height: 20),
            if (currentPoint == null)
              Text(
                'Location details are unavailable.',
                style: theme.textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  _Metric(
                    label: 'Accuracy',
                    value: '±${currentPoint.accuracy.toStringAsFixed(0)} m',
                  ),
                  if (currentPoint.speed != null)
                    _Metric(
                      label: 'Speed',
                      value:
                          '${(currentPoint.speed! * 3.6).toStringAsFixed(1)} km/h',
                    ),
                  if (currentPoint.heading != null)
                    _Metric(
                      label: 'Heading',
                      value: '${currentPoint.heading!.toStringAsFixed(0)}°',
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}
