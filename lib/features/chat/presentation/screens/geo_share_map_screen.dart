import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/location/maps/map_widgets.dart';
import '../../application/services/maps_diagnostics.dart';
import '../../domain/entities/geo_share.dart';

/// Read-only map showing a shared pin, route or arrival place.
class GeoShareMapScreen extends StatefulWidget {
  const GeoShareMapScreen({super.key, required this.share});

  final GeoShare share;

  /// Google Maps link that opens turn-by-turn directions for [share].
  static Uri directionsUri(GeoShare share) {
    final target = share.isRoute ? share.destination! : share.point;
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${target.latitude},${target.longitude}',
      if (share.isRoute)
        'origin': '${share.point.latitude},${share.point.longitude}',
    });
  }

  @override
  State<GeoShareMapScreen> createState() => _GeoShareMapScreenState();
}

class _GeoShareMapScreenState extends State<GeoShareMapScreen> {
  bool _mapConfigured = true;
  bool _myLocationEnabled = false;
  MapType _mapType = MapType.normal;
  bool _isDarkMap = false;
  bool _themeInitialized = false;
  bool _trafficEnabled = false;
  GoogleMapController? _map;
  CameraPosition? _cameraPosition;
  double _bearing = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPermissions());
    if (Platform.isAndroid) {
      unawaited(MapsDiagnostics.setMapActive(true));
      unawaited(_checkKey());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_themeInitialized) {
      _themeInitialized = true;
      _isDarkMap = Theme.of(context).brightness == Brightness.dark;
    }
  }

  @override
  void dispose() {
    _map?.dispose();
    if (Platform.isAndroid) unawaited(MapsDiagnostics.setMapActive(false));
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    final granted = await Permission.locationWhenInUse.isGranted;
    if (mounted && granted) {
      setState(() => _myLocationEnabled = true);
    }
  }

  Future<void> _checkKey() async {
    final diagnostics = await MapsDiagnostics.load();
    if (mounted && diagnostics != null && !diagnostics.keyPresent) {
      setState(() => _mapConfigured = false);
    }
  }

  LatLng _ll(GeoPoint p) => LatLng(p.latitude, p.longitude);

  Future<void> _fit(GoogleMapController c) async {
    final share = widget.share;
    if (!share.isRoute) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(_ll(share.point), 15));
      return;
    }
    final points = [share.point, share.destination!, ...share.path];
    var south = points.first.latitude;
    var north = south;
    var west = points.first.longitude;
    var east = west;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    if (south == north && west == east) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(_ll(share.point), 15));
      return;
    }
    // Wait a frame so the map has a size before fitting bounds.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        64,
      ),
    );
  }

  Future<void> _recenter() async {
    final controller = _map;
    if (controller == null) return;
    await _fit(controller);
  }

  @override
  Widget build(BuildContext context) {
    final share = widget.share;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(share.label.isEmpty ? share.preview : share.label),
        actions: [
          IconButton(
            tooltip: 'Open in Google Maps',
            icon: const Icon(Icons.directions_rounded),
            onPressed: () => launchUrl(
              GeoShareMapScreen.directionsUri(share),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: !_mapConfigured
          ? const Center(child: Text('Google Maps is not configured.'))
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _ll(share.point),
                    zoom: 15,
                  ),
                  mapType: _mapType,
                  style: _isDarkMap ? kDarkMapStyle : null,
                  trafficEnabled: _trafficEnabled,
                  onMapCreated: (c) {
                    _map = c;
                    if (share.isRoute) unawaited(_fit(c));
                  },
                  onCameraMove: (pos) {
                    _cameraPosition = pos;
                    if ((pos.bearing - _bearing).abs() > 0.5) {
                      setState(() => _bearing = pos.bearing);
                    }
                  },
                  markers: {
                    Marker(
                      markerId: const MarkerId('point'),
                      position: _ll(share.point),
                      infoWindow: InfoWindow(
                        title: share.isRoute ? 'Start' : share.label,
                      ),
                    ),
                    if (share.isRoute)
                      Marker(
                        markerId: const MarkerId('destination'),
                        position: _ll(share.destination!),
                        infoWindow: const InfoWindow(title: 'Destination'),
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueGreen,
                        ),
                      ),
                  },
                  polylines: {
                    if (share.isRoute)
                      Polyline(
                        polylineId: const PolylineId('route'),
                        color: _isDarkMap
                            ? const Color(0xFF81D4FA)
                            : const Color(0xFF1565C0),
                        width: 8,
                        startCap: Cap.roundCap,
                        endCap: Cap.roundCap,
                        points: [
                          for (final p
                              in share.path.isEmpty
                                  ? [share.point, share.destination!]
                                  : share.path)
                            _ll(p),
                        ],
                      ),
                  },
                  myLocationEnabled: _myLocationEnabled,
                  myLocationButtonEnabled: false,
                  compassEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    bottom: false,
                    child: MapOverlayControls(
                      bearing: _bearing,
                      onResetBearing: () =>
                          unawaited(resetMapBearing(_map, _cameraPosition)),
                      mapType: _mapType,
                      onMapTypeChanged: (t) => setState(() => _mapType = t),
                      isDarkMap: _isDarkMap,
                      onDarkMapChanged: (v) => setState(() => _isDarkMap = v),
                      trafficEnabled: _trafficEnabled,
                      onTrafficChanged: (v) =>
                          setState(() => _trafficEnabled = v),
                      onLocateMe: _recenter,
                      locateTooltip: 'Re-center',
                      locateIcon: Icons.center_focus_strong_rounded,
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: SafeArea(
                    top: false,
                    child: Material(
                      color: cs.surfaceContainerHigh,
                      elevation: 2,
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    share.label.isEmpty
                                        ? (share.isRoute
                                              ? 'Shared route'
                                              : 'Pinned location')
                                        : share.label,
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (share.distanceMeters != null ||
                                      share.durationSeconds != null) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (share.distanceMeters != null)
                                          _MetricChip(
                                            icon: Icons.straighten_rounded,
                                            label:
                                                '${(share.distanceMeters! / 1000).toStringAsFixed(1)} km',
                                          ),
                                        if (share.durationSeconds != null)
                                          _MetricChip(
                                            icon: Icons.schedule_rounded,
                                            label:
                                                RouteSummaryChip.formatDuration(
                                                  share.durationSeconds!,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: () => launchUrl(
                                GeoShareMapScreen.directionsUri(share),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(
                                Icons.directions_rounded,
                                size: 18,
                              ),
                              label: const Text('Directions'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: cs.onSecondaryContainer),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
