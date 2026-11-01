import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/location/app_location.dart';
import '../../application/services/maps_diagnostics.dart';
import '../../domain/entities/live_location.dart';

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
  MapsDiagnostics? _diagnostics;
  LiveLocationPoint? _deviceFallbackPoint;
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (Platform.isAndroid) {
      unawaited(MapsDiagnostics.setMapActive(true));
      unawaited(_loadEnvironment());
    }
  }

  Future<void> _loadEnvironment() async {
    final diagnostics = await MapsDiagnostics.load();
    final granted = await Permission.locationWhenInUse.isGranted;
    if (mounted) {
      setState(() {
        _diagnostics = diagnostics;
        _locationGranted = granted;
      });
    }
    if (granted || AppLocation.instance.isMocking) {
      try {
        final location = AppLocation.instance;
        final last = await location.lastKnown();
        if (last != null && mounted) {
          setState(() {
            _deviceFallbackPoint = LiveLocationPoint(
              latitude: last.latitude,
              longitude: last.longitude,
              accuracy: last.accuracy,
              timestamp: last.timestamp,
            );
          });
        }
        final current = await location.current(
          timeLimit: const Duration(seconds: 6),
        );
        if (mounted) {
          setState(() {
            _deviceFallbackPoint = LiveLocationPoint(
              latitude: current.latitude,
              longitude: current.longitude,
              accuracy: current.accuracy,
              timestamp: current.timestamp,
            );
          });
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    if (Platform.isAndroid) {
      unawaited(MapsDiagnostics.setMapActive(false));
    }
    super.dispose();
  }

  void _showDiagnosticsDialog(BuildContext context, MapsDiagnostics diag) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.map_outlined),
        title: const Text('Google Maps Diagnostics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Package: ${diag.packageName ?? 'com.system.calculator'}'),
            const SizedBox(height: 6),
            Text(
              'API Key: ${diag.keyPresent ? (diag.keyMasked ?? 'Configured') : 'MISSING in AndroidManifest'}',
            ),
            const SizedBox(height: 6),
            SelectableText('Signing SHA-1:\n${diag.signingSha1 ?? 'Unknown'}'),
            const SizedBox(height: 12),
            Text(
              'Ensure Maps SDK for Android is enabled in Google Cloud Console and the API key allows this package name and SHA-1.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (diag.signingSha1 != null)
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: diag.signingSha1!));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('SHA-1 copied to clipboard.')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy SHA-1'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
    final point = session?.currentPoint;
    final effectivePoint =
        point ?? (widget.isMine ? _deviceFallbackPoint : null);
    final isLive = session?.isLive ?? false;
    final isStale = session?.isStale ?? false;
    final isActive = session?.isActive == true && session?.isExpired == false;
    final mapConfigured = _diagnostics?.keyPresent ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isActive
                  ? (widget.isMine ? 'Your Live Location' : 'Live Location')
                  : (widget.isMine
                        ? 'Your Last Known Location'
                        : 'Last Known Location'),
            ),
            Text(
              _statusLabel(session, isActive, isLive, isStale),
              style: theme.textTheme.labelSmall?.copyWith(
                color: isLive ? (isStale ? Colors.amber : Colors.green) : null,
              ),
            ),
          ],
        ),
        actions: [
          if (_diagnostics != null)
            IconButton(
              tooltip: 'Map diagnostics',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => _showDiagnosticsDialog(context, _diagnostics!),
            ),
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
                        'Google Maps is not configured. Set GOOGLE_MAPS_ANDROID_API_KEY in .api_keys.json.',
                  )
                : _LiveGoogleMap(
                    point: effectivePoint,
                    isActive: isActive,
                    isMine: widget.isMine,
                    lastUpdatedAt: session?.lastUpdatedAt,
                    myLocationEnabled: _locationGranted,
                  ),
          ),
          if (mapConfigured && effectivePoint == null)
            Positioned(
              left: 16,
              right: 16,
              top: 12,
              child: Card(
                color: colors.surfaceContainerHigh.withValues(alpha: 0.92),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: isActive
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : const Icon(Icons.location_off_outlined, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isActive
                              ? 'Waiting for the sender’s first location…'
                              : 'Location session ended and no coordinates were recorded.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                point: effectivePoint,
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
    final timeStr = DateFormat.jm().format(session.lastUpdatedAt.toLocal());
    return session.isExpired
        ? 'Session expired at $timeStr'
        : 'Sharing stopped at $timeStr';
  }
}

class _LiveGoogleMap extends StatefulWidget {
  const _LiveGoogleMap({
    required this.point,
    required this.isActive,
    required this.isMine,
    required this.myLocationEnabled,
    this.lastUpdatedAt,
  });

  final LiveLocationPoint? point;
  final bool isActive;
  final bool isMine;
  final bool myLocationEnabled;
  final DateTime? lastUpdatedAt;

  @override
  State<_LiveGoogleMap> createState() => _LiveGoogleMapState();
}

class _LiveGoogleMapState extends State<_LiveGoogleMap> {
  static const _defaultCenter = LatLng(20.5937, 78.9629);
  GoogleMapController? _controller;

  @override
  void didUpdateWidget(covariant _LiveGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.point;
    final prev = oldWidget.point;
    if (next != null &&
        (prev == null ||
            prev.latitude != next.latitude ||
            prev.longitude != next.longitude)) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(next.latitude, next.longitude), 16),
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
    final center = point != null
        ? LatLng(point.latitude, point.longitude)
        : _defaultCenter;
    final markerTitle = widget.isActive
        ? (widget.isMine ? 'Your live location' : 'Shared live location')
        : (widget.isMine ? 'Your last known location' : 'Last known location');
    final updatedAt =
        widget.lastUpdatedAt ?? point?.timestamp ?? DateTime.now();
    final markerSnippet = point == null
        ? ''
        : [
            if (!widget.isActive)
              'Last seen ${DateFormat.jm().format(updatedAt.toLocal())}',
            'Accuracy ±${point.accuracy.toStringAsFixed(0)} m',
            if (point.heading != null)
              'Heading ${point.heading!.toStringAsFixed(0)}°',
          ].join(' · ');

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: center,
        zoom: point != null ? 16 : 5,
      ),
      onMapCreated: (controller) => _controller = controller,
      markers: point == null
          ? const <Marker>{}
          : {
              Marker(
                markerId: const MarkerId('shared-location'),
                position: center,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  widget.isActive
                      ? BitmapDescriptor.hueAzure
                      : BitmapDescriptor.hueOrange,
                ),
                infoWindow: InfoWindow(
                  title: markerTitle,
                  snippet: markerSnippet,
                ),
              ),
            },
      circles: point == null
          ? const <Circle>{}
          : {
              Circle(
                circleId: const CircleId('location-accuracy'),
                center: center,
                radius: math.max(point.accuracy, 5.0),
                fillColor: (widget.isActive ? Colors.blue : Colors.orange)
                    .withValues(alpha: 0.12),
                strokeColor: (widget.isActive ? Colors.blue : Colors.orange)
                    .withValues(alpha: 0.5),
                strokeWidth: 1,
              ),
            },
      myLocationEnabled: widget.myLocationEnabled,
      myLocationButtonEnabled: widget.myLocationEnabled,
      zoomControlsEnabled: true,
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
                        : session.isExpired
                        ? 'Live location expired'
                        : 'Sharing stopped',
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
