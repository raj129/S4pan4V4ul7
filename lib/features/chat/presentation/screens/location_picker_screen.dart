import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/location/app_location.dart';
import '../../../../core/location/geo_fix.dart';
import '../../../../core/location/maps/map_widgets.dart';
import '../../../../core/location/mock/sim_route.dart';
import '../../application/services/directions_service.dart';
import '../../application/services/maps_diagnostics.dart';
import '../../application/services/place_search_service.dart';
import '../../domain/entities/arrival_alert.dart';
import '../../domain/entities/geo_share.dart';
import '../../domain/entities/saved_place.dart';

enum _PickMode { pin, route }

enum _End { origin, destination }

/// A place chosen for an arrival alert, with the radius shown on the map.
class ArrivalPlacePick {
  const ArrivalPlacePick({required this.share, required this.radiusMeters});

  final GeoShare share;
  final double radiusMeters;
}

/// Full-screen map for choosing a pin, or a route between two points.
///
/// Places can be searched or marked on the map. In route mode the route for
/// the chosen transport mode is drawn as soon as both ends are set.
/// Pops with a [GeoShare] when the user confirms, or null when cancelled.
/// With [showRadius] it is the arrival place chooser: it draws the geofence
/// circle, lets the user set the radius, and pops an [ArrivalPlacePick].
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.allowRoute = true,
    this.requireLabel = false,
    this.title = 'Share location',
    this.confirmLabel = 'Send',
    this.directions,
    this.places,
    this.showRadius = false,
    this.initialRadius = ArrivalAlert.defaultRadiusMeters,
    this.savedPlaces = const [],
    this.initialPin,
    this.initialLabel = '',
  });

  final bool allowRoute;
  final bool requireLabel;
  final String title;
  final String confirmLabel;
  final DirectionsService? directions;
  final PlaceSearchService? places;

  /// Arrival mode: shows the radius slider and the geofence circle.
  final bool showRadius;
  final double initialRadius;

  /// Saved places drawn as circles so overlaps are visible.
  final List<SavedPlace> savedPlaces;

  /// A place to start from, such as the one being edited.
  final GeoPoint? initialPin;
  final String initialLabel;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _labelController = TextEditingController();
  late final DirectionsService _directions =
      widget.directions ?? DirectionsService();
  late final PlaceSearchService _places = widget.places ?? PlaceSearchService();
  final _searchController = TextEditingController();
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  bool _searchReady = true;
  GoogleMapController? _map;
  _PickMode _mode = _PickMode.pin;
  TravelProfile _travel = TravelProfile.drive;
  _End _active = _End.origin;
  GeoPoint? _pin;
  GeoPoint? _origin;
  GeoPoint? _destination;
  GeoShare? _route;
  GeoPoint? _current;
  late double _radius = widget.initialRadius;
  bool _mapConfigured = true;
  bool _loadingRoute = false;
  String? _error;
  Timer? _routeTimer;
  int _routeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _pin = widget.initialPin;
    _labelController.text = widget.initialLabel;
    if (Platform.isAndroid) {
      unawaited(MapsDiagnostics.setMapActive(true));
      unawaited(_loadEnvironment());
    }
    unawaited(
      _places.isConfigured.then((ready) {
        if (mounted) setState(() => _searchReady = ready);
      }),
    );
  }

  @override
  void dispose() {
    if (Platform.isAndroid) unawaited(MapsDiagnostics.setMapActive(false));
    _routeTimer?.cancel();
    _labelController.dispose();
    _searchController.dispose();
    _originController.dispose();
    _destinationController.dispose();
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
      final location = AppLocation.instance;
      if (!location.isMocking) {
        final status = await Permission.locationWhenInUse.request();
        if (!status.isGranted) {
          if (!quiet) _fail('Allow location access to use your position.');
          return;
        }
      }
      if (!await location.isServiceEnabled()) {
        if (!quiet) _fail('Turn on device location services.');
        return;
      }
      final position = await location.current().timeout(
        const Duration(seconds: 15),
      );
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

  void _place(GeoPoint point, {String? text}) {
    setState(() {
      _error = null;
      if (_mode == _PickMode.pin) {
        _pin = point;
        return;
      }
      if (_active == _End.origin) {
        _origin = point;
        _originController.text = text ?? _format(point);
        _active = _End.destination;
      } else {
        _destination = point;
        _destinationController.text = text ?? _format(point);
      }
    });
    if (_mode == _PickMode.route) _scheduleRoute();
  }

  static String _format(GeoPoint p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

  /// Recomputes the route shortly after either end or the mode changes.
  void _scheduleRoute() {
    _routeTimer?.cancel();
    _routeGeneration++;
    setState(() => _route = null);
    if (_origin == null || _destination == null) return;
    _routeTimer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_buildRoute()),
    );
  }

  Future<void> _buildRoute() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return;
    final generation = ++_routeGeneration;
    setState(() {
      _loadingRoute = true;
      _error = null;
    });
    try {
      final route = await _directions.fetchRoute(
        origin: origin,
        destination: destination,
        label: _labelController.text.trim(),
        mode: _travel,
      );
      if (!mounted || generation != _routeGeneration) return;
      setState(() => _route = route);
      final bounds = _bounds([origin, destination, ...route.path]);
      await _map?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
    } catch (error) {
      if (mounted && generation == _routeGeneration) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _routeGeneration) {
        setState(() => _loadingRoute = false);
      }
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
      final share = GeoShare.pin(point: _pin!, label: label);
      Navigator.of(context).pop(
        widget.showRadius
            ? ArrivalPlacePick(share: share, radiusMeters: _radius)
            : share,
      );
    } else {
      final route = _route!;
      Navigator.of(context).pop(
        GeoShare.route(
          origin: route.point,
          destination: route.destination!,
          label: label,
          path: route.path,
          distanceMeters: route.distanceMeters,
          durationSeconds: route.durationSeconds,
          mode: route.mode,
        ),
      );
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

  /// Geofence circles: the saved places, and the chosen pin in arrival mode.
  Set<Circle> get _circles {
    final cs = Theme.of(context).colorScheme;
    return {
      for (final place in widget.savedPlaces)
        Circle(
          circleId: CircleId('saved-${place.id}'),
          center: _latLng(place.point),
          radius: place.radiusMeters,
          strokeWidth: 1,
          strokeColor: Color(place.tagColor ?? 0xFF757575),
          fillColor: Color(
            place.tagColor ?? 0xFF757575,
          ).withValues(alpha: 0.12),
        ),
      if (widget.showRadius && _mode == _PickMode.pin && _pin != null)
        Circle(
          circleId: const CircleId('arrival'),
          center: _latLng(_pin!),
          radius: _radius,
          strokeWidth: 2,
          strokeColor: cs.primary,
          fillColor: cs.primary.withValues(alpha: 0.18),
        ),
    };
  }

  String get _hint {
    if (_mode == _PickMode.pin) {
      return _pin == null
          ? 'Search a place or tap the map to drop a pin'
          : 'Pin placed';
    }
    if (_origin == null) return 'Search or tap the map to set the start';
    if (_destination == null) {
      return 'Search or tap the map to set the destination';
    }
    if (_loadingRoute) return 'Finding the best route…';
    return _route == null ? 'Route unavailable' : 'Ready to send';
  }

  bool get _searchEnabled => Platform.isAndroid && _mapConfigured;

  Future<List<PlaceHit>> _search(String query) async {
    final coord = parseCoordinateQuery(query);
    if (coord != null) {
      return [
        PlaceHit(name: coord.toString(), address: 'Coordinates', coord: coord),
      ];
    }
    if (!_searchReady) {
      throw PlaceSearchException(
        'Place search needs a Google Maps key in this build.',
      );
    }
    final results = await _places.search(query, near: _current);
    return [
      for (final r in results)
        PlaceHit(
          name: r.name,
          address: r.address,
          coord: GeoCoord(r.point.latitude, r.point.longitude),
        ),
    ];
  }

  Future<void> _selectHit(PlaceHit hit, {_End? end}) async {
    final point = GeoPoint(hit.coord.latitude, hit.coord.longitude);
    if (end != null) _active = end;
    _place(point, text: hit.name);
    if (_mode == _PickMode.pin && _labelController.text.trim().isEmpty) {
      _labelController.text = hit.name;
    }
    await _map?.animateCamera(CameraUpdate.newLatLngZoom(_latLng(point), 16));
  }

  Widget _buildSearch(ColorScheme cs) {
    if (_mode == _PickMode.pin) {
      return PlaceSearchField(
        key: const Key('picker-search'),
        controller: _searchController,
        hint: 'Search places',
        search: _search,
        onSelected: _selectHit,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PlaceSearchField(
          key: const Key('picker-search-origin'),
          controller: _originController,
          label: 'Start',
          hint: 'Search a start place',
          icon: Icons.trip_origin,
          iconColor: Colors.green,
          highlighted: _active == _End.origin,
          search: _search,
          onFocused: () => setState(() => _active = _End.origin),
          onSelected: (hit) => _selectHit(hit, end: _End.origin),
          onLocateMe: () async {
            final here = _current;
            if (here == null) {
              await _locateMe(moveCamera: true);
            }
            final point = _current;
            if (point == null) return;
            _active = _End.origin;
            _place(point, text: 'My location');
          },
        ),
        const SizedBox(height: 8),
        PlaceSearchField(
          key: const Key('picker-search-destination'),
          controller: _destinationController,
          label: 'Destination',
          hint: 'Search a destination',
          icon: Icons.place,
          iconColor: Colors.red,
          highlighted: _active == _End.destination,
          search: _search,
          onFocused: () => setState(() => _active = _End.destination),
          onSelected: (hit) => _selectHit(hit, end: _End.destination),
        ),
        const SizedBox(height: 8),
        Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          child: TransportModeSelector(
            selected: _travel,
            onChanged: (mode) {
              setState(() => _travel = mode);
              _scheduleRoute();
            },
          ),
        ),
      ],
    );
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
                          target: widget.initialPin != null
                              ? _latLng(widget.initialPin!)
                              : _current == null
                              ? const LatLng(20, 0)
                              : _latLng(_current!),
                          zoom: widget.initialPin != null
                              ? 15
                              : _current == null
                              ? 2
                              : 15,
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
                        circles: _circles,
                        myLocationEnabled: _current != null,
                        myLocationButtonEnabled: false,
                        mapToolbarEnabled: false,
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.allowRoute)
                              SegmentedButton<_PickMode>(
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
                            if (_searchEnabled) ...[
                              if (widget.allowRoute) const SizedBox(height: 8),
                              _buildSearch(cs),
                            ],
                          ],
                        ),
                      ),
                      if (widget.showRadius)
                        Positioned(
                          left: 12,
                          right: 72,
                          bottom: 12,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Alert within ${_radius.round()} m',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                  Slider(
                                    min: 100,
                                    max: 1000,
                                    divisions: 18,
                                    value: _radius,
                                    label: '${_radius.round()} m',
                                    onChanged: (v) =>
                                        setState(() => _radius = v),
                                  ),
                                ],
                              ),
                            ),
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
                            color: _error == null
                                ? cs.onSurfaceVariant
                                : cs.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_mode == _PickMode.route && _route != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: RouteSummaryChip(
                                mode: _travel,
                                distanceMeters: _route!.distanceMeters ?? 0,
                                durationSeconds: _route!.durationSeconds,
                              ),
                            ),
                          ),
                        if (_mode == _PickMode.route &&
                            _error != null &&
                            !_loadingRoute)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _buildRoute,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry route'),
                            ),
                          ),
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
                        FilledButton.icon(
                          onPressed: _canConfirm ? _confirm : null,
                          icon: _loadingRoute
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
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
