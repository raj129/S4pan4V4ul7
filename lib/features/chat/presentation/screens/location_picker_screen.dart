import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../application/services/directions_service.dart';
import '../../application/services/maps_diagnostics.dart';
import '../../domain/entities/geo_share.dart';

enum _PickMode { pin, route }

/// Full-screen map for choosing a pin, or a route between two points.
///
/// Pops with a [GeoShare] when the user confirms, or null when cancelled.
/// With [allowRoute] false it behaves as a single-place chooser, used for
/// arrival alerts.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.allowRoute = true,
    this.requireLabel = false,
    this.title = 'Share location',
    this.confirmLabel = 'Send',
    this.directions,
  });

  final bool allowRoute;
  final bool requireLabel;
  final String title;
  final String confirmLabel;
  final DirectionsService? directions;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _labelController = TextEditingController();
  late final DirectionsService _directions =
      widget.directions ?? DirectionsService();
  GoogleMapController? _map;
  _PickMode _mode = _PickMode.pin;
  GeoPoint? _pin;
  GeoPoint? _origin;
  GeoPoint? _destination;
  GeoShare? _route;
  GeoPoint? _current;
  bool _mapConfigured = true;
  bool _loadingRoute = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      unawaited(MapsDiagnostics.setMapActive(true));
      unawaited(_loadEnvironment());
    }
  }

  @override
  void dispose() {
    if (Platform.isAndroid) unawaited(MapsDiagnostics.setMapActive(false));
    _labelController.dispose();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _loadEnvironment() async {
    final diagnostics = await MapsDiagnostics.load();
    if (mounted && diagnostics != null && !diagnostics.keyPresent) {
      setState(() => _mapConfigured = false);
    }
    if (await Permission.locationWhenInUse.isGranted) {
      await _locateMe(moveCamera: true, quiet: true);
    }
  }

  Future<void> _locateMe({bool moveCamera = false, bool quiet = false}) async {
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        if (!quiet) _fail('Allow location access to use your position.');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!quiet) _fail('Turn on device location services.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));
      final point = GeoPoint(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _current = point);
      if (moveCamera) {
        await _map?.animateCamera(
          CameraUpdate.newLatLngZoom(_latLng(point), 15),
        );
      } else {
        _place(point);
      }
    } catch (error) {
      if (!quiet) _fail('Could not get your location: $error');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  LatLng _latLng(GeoPoint p) => LatLng(p.latitude, p.longitude);

  void _place(GeoPoint point) {
    setState(() {
      _error = null;
      if (_mode == _PickMode.pin) {
        _pin = point;
      } else if (_origin == null || (_origin != null && _destination != null)) {
        _origin = point;
        _destination = null;
        _route = null;
      } else {
        _destination = point;
        _route = null;
      }
    });
  }

  Future<void> _buildRoute() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return;
    setState(() {
      _loadingRoute = true;
      _error = null;
    });
    try {
      final route = await _directions.fetchRoute(
        origin: origin,
        destination: destination,
        label: _labelController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _route = route);
      final bounds = _bounds([origin, destination, ...route.path]);
      await _map?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  LatLngBounds _bounds(List<GeoPoint> points) {
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
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  bool get _canConfirm {
    if (widget.requireLabel && _labelController.text.trim().isEmpty) {
      return false;
    }
    return _mode == _PickMode.pin ? _pin != null : _route != null;
  }

  void _confirm() {
    final label = _labelController.text.trim();
    if (_mode == _PickMode.pin) {
      Navigator.of(context).pop(GeoShare.pin(point: _pin!, label: label));
    } else {
      Navigator.of(context).pop(_route);
    }
  }

  Set<Marker> get _markers => {
    if (_mode == _PickMode.pin && _pin != null)
      Marker(markerId: const MarkerId('pin'), position: _latLng(_pin!)),
    if (_mode == _PickMode.route && _origin != null)
      Marker(
        markerId: const MarkerId('origin'),
        position: _latLng(_origin!),
        infoWindow: const InfoWindow(title: 'Start'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    if (_mode == _PickMode.route && _destination != null)
      Marker(
        markerId: const MarkerId('destination'),
        position: _latLng(_destination!),
        infoWindow: const InfoWindow(title: 'Destination'),
      ),
  };

  Set<Polyline> get _polylines => {
    if (_route != null)
      Polyline(
        polylineId: const PolylineId('route'),
        color: Theme.of(context).colorScheme.primary,
        width: 5,
        points: [for (final p in _route!.path) _latLng(p)],
      ),
  };

  String get _hint {
    if (_mode == _PickMode.pin) {
      return _pin == null ? 'Tap the map to drop a pin' : 'Pin placed';
    }
    if (_origin == null) return 'Tap the map to set the start';
    if (_destination == null) return 'Tap the map to set the destination';
    return 'Tap Get route, or tap again to start over';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: !_mapConfigured
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Google Maps is not configured. Set '
                  'GOOGLE_MAPS_ANDROID_API_KEY in .api_keys.json.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _current == null
                              ? const LatLng(20, 0)
                              : _latLng(_current!),
                          zoom: _current == null ? 2 : 15,
                        ),
                        onMapCreated: (c) {
                          _map = c;
                          final current = _current;
                          if (current != null) {
                            unawaited(
                              c.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  _latLng(current),
                                  15,
                                ),
                              ),
                            );
                          }
                        },
                        onTap: (latLng) =>
                            _place(GeoPoint(latLng.latitude, latLng.longitude)),
                        markers: _markers,
                        polylines: _polylines,
                        myLocationEnabled: _current != null,
                        myLocationButtonEnabled: false,
                        mapToolbarEnabled: false,
                      ),
                      if (widget.allowRoute)
                        Positioned(
                          top: 12,
                          left: 12,
                          right: 12,
                          child: SegmentedButton<_PickMode>(
                            style: SegmentedButton.styleFrom(
                              backgroundColor: cs.surface,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: _PickMode.pin,
                                icon: Icon(Icons.place_rounded),
                                label: Text('Pin'),
                              ),
                              ButtonSegment(
                                value: _PickMode.route,
                                icon: Icon(Icons.alt_route_rounded),
                                label: Text('Route'),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (s) =>
                                setState(() => _mode = s.first),
                          ),
                        ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: FloatingActionButton.small(
                          heroTag: 'picker-locate',
                          tooltip: 'Use my location',
                          onPressed: _locateMe,
                          child: const Icon(Icons.my_location_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _error ?? _hint,
                          style: TextStyle(
                            color: _error == null ? cs.onSurfaceVariant : cs.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _labelController,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: widget.requireLabel
                                ? 'Place name'
                                : 'Label (optional)',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_mode == _PickMode.route && _route == null)
                          FilledButton.icon(
                            onPressed:
                                _origin != null &&
                                    _destination != null &&
                                    !_loadingRoute
                                ? _buildRoute
                                : null,
                            icon: _loadingRoute
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.directions_rounded),
                            label: const Text('Get route'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _canConfirm ? _confirm : null,
                            icon: const Icon(Icons.send_rounded),
                            label: Text(widget.confirmLabel),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
