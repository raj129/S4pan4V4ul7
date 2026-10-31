import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      unawaited(MapsDiagnostics.setMapActive(true));
      unawaited(_checkKey());
    }
  }

  @override
  void dispose() {
    if (Platform.isAndroid) unawaited(MapsDiagnostics.setMapActive(false));
    super.dispose();
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
    if (!share.isRoute) return;
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

  @override
  Widget build(BuildContext context) {
    final share = widget.share;
    final cs = Theme.of(context).colorScheme;
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
          : GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _ll(share.point),
                zoom: 15,
              ),
              onMapCreated: (c) => unawaited(_fit(c)),
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
                    color: cs.primary,
                    width: 5,
                    points: [
                      for (final p in share.path.isEmpty
                          ? [share.point, share.destination!]
                          : share.path)
                        _ll(p),
                    ],
                  ),
              },
              mapToolbarEnabled: false,
            ),
    );
  }
}
