import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
  CameraPosition? _cameraPosition;
  double _bearing = 0;
  _PickMode _mode = _PickMode.pin;
  TravelProfile _travel = TravelProfile.drive;
  _End _active = _End.origin;
  MapType _mapType = MapType.normal;
  bool _isDarkMap = false;
  bool _themeInitialized = false;
  bool _trafficEnabled = false;
  bool _routePanelCollapsed = false;
  GeoPoint? _pin;
  GeoPoint? _origin;
  GeoPoint? _destination;
  List<RouteOption> _routeOptions = const [];
  Map<int, BitmapDescriptor> _etaCalloutIcons = const {};
  int _selectedRouteIndex = 0;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_themeInitialized) {
      _themeInitialized = true;
      _isDarkMap = Theme.of(context).brightness == Brightness.dark;
    }
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

  List<GeoShare> get _routes => [for (final o in _routeOptions) o.share];

  RouteOption? get _selectedOption =>
      _routeOptions.isEmpty ? null : _routeOptions[_selectedRouteIndex];

  GeoShare? get _route => _selectedOption?.share;

  /// Recomputes the route shortly after either end or the mode changes.
  void _scheduleRoute() {
    _routeTimer?.cancel();
    _routeGeneration++;
    setState(() {
      _routeOptions = const [];
      _etaCalloutIcons = const {};
      _selectedRouteIndex = 0;
    });
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
      final options = await _directions.fetchRouteOptions(
        origin: origin,
        destination: destination,
        label: _labelController.text.trim(),
        mode: _travel,
      );
      if (!mounted || generation != _routeGeneration) return;
      setState(() {
        _routeOptions = options;
        _selectedRouteIndex = 0;
        _routePanelCollapsed = true;
      });
      unawaited(_rebuildEtaCalloutIcons(generation));
      final bounds = _bounds([origin, destination, ...options.first.share.path]);
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

  Future<void> _rebuildEtaCalloutIcons([int? generation]) async {
    if (_routeOptions.isEmpty) return;
    final icons = <int, BitmapDescriptor>{};
    for (var i = 0; i < _routeOptions.length; i++) {
      final share = _routeOptions[i].share;
      if (share.durationSeconds == null) continue;
      final durationText = RouteSummaryChip.formatDuration(
        share.durationSeconds!,
      );
      final isSelected = i == _selectedRouteIndex;
      final label = isSelected
          ? durationText
          : '$durationText (${_etaDiffLabel(i)})';
      icons[i] = await _drawEtaPill(
        label: label,
        selected: isSelected,
        darkMap: _isDarkMap,
      );
    }
    if (!mounted) return;
    if (generation != null && generation != _routeGeneration) return;
    setState(() => _etaCalloutIcons = icons);
  }

  static Future<BitmapDescriptor> _drawEtaPill({
    required String label,
    required bool selected,
    required bool darkMap,
  }) async {
    const scale = 2.0;
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 12 * scale,
          fontWeight: FontWeight.w700,
          color: selected
              ? (darkMap ? const Color(0xFF0A1929) : Colors.white)
              : (darkMap ? Colors.white : const Color(0xFF1F2937)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padX = 10.0 * scale;
    const padY = 6.0 * scale;
    final width = textPainter.width + padX * 2;
    final height = textPainter.height + padY * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 2, width - 4, height - 4),
      Radius.circular(height / 2),
    );
    final fillColor = selected
        ? (darkMap ? const Color(0xFF81D4FA) : const Color(0xFF1565C0))
        : (darkMap ? const Color(0xFF263238) : Colors.white);
    final borderColor = selected
        ? Colors.transparent
        : (darkMap ? const Color(0xFF607D8B) : const Color(0xFFB0BEC5));

    canvas.drawRRect(
      rect,
      Paint()
        ..color = Colors.black38
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(rect, Paint()..color = fillColor);
    if (!selected) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    textPainter.paint(canvas, Offset(padX, padY));

    final image = await recorder.endRecording().toImage(
      width.ceil(),
      height.ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: width / scale,
      height: height / scale,
    );
  }

  void _selectRoute(int index) {
    if (index == _selectedRouteIndex) return;
    setState(() => _selectedRouteIndex = index);
    unawaited(_rebuildEtaCalloutIcons());
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

  String _etaDiffLabel(int routeIndex) {
    final selectedSec = _route?.durationSeconds;
    final otherSec = _routes[routeIndex].durationSeconds;
    if (selectedSec == null || otherSec == null) return 'Alternative';
    final diffMin = ((otherSec - selectedSec) / 60).round();
    if (diffMin == 0) return 'Same ETA';
    return diffMin > 0 ? '+$diffMin min' : '$diffMin min';
  }

  Set<Marker> get _markers => {
    if (_mode == _PickMode.pin && _pin != null)
      Marker(
        markerId: const MarkerId('pin'),
        position: _latLng(_pin!),
        draggable: true,
        onDragEnd: (latLng) => setState(() {
          _error = null;
          _pin = GeoPoint(latLng.latitude, latLng.longitude);
        }),
      ),
    if (_mode == _PickMode.route && _origin != null)
      Marker(
        markerId: const MarkerId('origin'),
        position: _latLng(_origin!),
        draggable: true,
        onDragEnd: (latLng) {
          final point = GeoPoint(latLng.latitude, latLng.longitude);
          setState(() {
            _error = null;
            _origin = point;
            _originController.text = _format(point);
          });
          _scheduleRoute();
        },
        infoWindow: const InfoWindow(title: 'Start'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    if (_mode == _PickMode.route && _destination != null)
      Marker(
        markerId: const MarkerId('destination'),
        position: _latLng(_destination!),
        draggable: true,
        onDragEnd: (latLng) {
          final point = GeoPoint(latLng.latitude, latLng.longitude);
          setState(() {
            _error = null;
            _destination = point;
            _destinationController.text = _format(point);
          });
          _scheduleRoute();
        },
        infoWindow: const InfoWindow(title: 'Destination'),
      ),
    if (_mode == _PickMode.route && _routeOptions.isNotEmpty)
      for (var i = 0; i < _routeOptions.length; i++)
        if (_routeOptions[i].share.path.isNotEmpty &&
            _etaCalloutIcons.containsKey(i))
          Marker(
            markerId: MarkerId('route-eta-$i'),
            position: _latLng(
              _routeOptions[i].share.path[
                _routeOptions[i].share.path.length ~/ 2
              ],
            ),
            anchor: const Offset(0.5, 0.5),
            zIndexInt: i == _selectedRouteIndex ? 2 : 1,
            icon: _etaCalloutIcons[i]!,
            onTap: () => _selectRoute(i),
          ),
  };

  Set<Polyline> get _polylines {
    final primaryColor = _isDarkMap
        ? const Color(0xFF81D4FA)
        : const Color(0xFF1565C0);
    final altColor = _isDarkMap
        ? const Color(0xFF90A4AE)
        : const Color(0xFF546E7A);
    final polylines = <Polyline>{};

    // Draw unselected alternatives underneath.
    for (var i = 0; i < _routeOptions.length; i++) {
      if (i == _selectedRouteIndex) continue;
      polylines.add(
        Polyline(
          polylineId: PolylineId('route-$i'),
          color: altColor,
          width: 6,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 0,
          consumeTapEvents: true,
          onTap: () => _selectRoute(i),
          points: [for (final p in _routeOptions[i].share.path) _latLng(p)],
        ),
      );
    }

    final selected = _selectedOption;
    if (selected == null) return polylines;

    // Transit route: draw each metro/rail leg in its official line color.
    if (selected.transitSegments.isNotEmpty) {
      for (var s = 0; s < selected.transitSegments.length; s++) {
        final seg = selected.transitSegments[s];
        polylines.add(
          Polyline(
            polylineId: PolylineId('transit-seg-$s'),
            color: seg.isTransit
                ? (seg.lineColor ?? primaryColor)
                : altColor,
            width: seg.isTransit ? 8 : 5,
            patterns: seg.isTransit
                ? const <PatternItem>[]
                : [PatternItem.dot, PatternItem.gap(8)],
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            zIndex: seg.isTransit ? 2 : 1,
            points: [for (final p in seg.points) _latLng(p)],
          ),
        );
      }
      return polylines;
    }

    // Base primary polyline.
    polylines.add(
      Polyline(
        polylineId: PolylineId('route-$_selectedRouteIndex'),
        color: primaryColor,
        width: 8,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: 1,
        points: [for (final p in selected.share.path) _latLng(p)],
      ),
    );

    // Overlay slow/jam traffic segments on top of the selected route.
    final pts = selected.share.path;
    for (var t = 0; t < selected.trafficSpans.length; t++) {
      final span = selected.trafficSpans[t];
      if (span.band != TrafficBand.slow && span.band != TrafficBand.jam) {
        continue;
      }
      final start = math.max(0, span.startIndex);
      final end = math.min(pts.length - 1, span.endIndex);
      if (end <= start) continue;
      polylines.add(
        Polyline(
          polylineId: PolylineId('traffic-$t'),
          color: span.band == TrafficBand.jam
              ? const Color(0xFFE53935)
              : const Color(0xFFFB8C00),
          width: 8,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 2,
          points: [for (var idx = start; idx <= end; idx++) _latLng(pts[idx])],
        ),
      );
    }

    return polylines;
  }

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

  void _swapEnds() {
    setState(() {
      final tempPoint = _origin;
      _origin = _destination;
      _destination = tempPoint;

      final tempText = _originController.text;
      _originController.text = _destinationController.text;
      _destinationController.text = tempText;

      _active = _active == _End.origin ? _End.destination : _End.origin;
      _error = null;
    });
    _scheduleRoute();
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
    final textTheme = Theme.of(context).textTheme;
    if (_routePanelCollapsed) {
      final originLabel = _originController.text.trim().isEmpty
          ? 'Set start'
          : _originController.text.trim();
      final destLabel = _destinationController.text.trim().isEmpty
          ? 'Set destination'
          : _destinationController.text.trim();
      return Material(
        color: cs.surfaceContainerHigh,
        elevation: 2,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _routePanelCollapsed = false),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(
              children: [
                Icon(
                  TransportModeSelector.iconFor(_travel),
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$originLabel → $destLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Swap start and destination',
                  visualDensity: VisualDensity.compact,
                  onPressed: (_origin != null || _destination != null)
                      ? _swapEnds
                      : null,
                  icon: const Icon(Icons.swap_vert_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Expand route panel',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _routePanelCollapsed = false),
                  icon: const Icon(Icons.expand_more_rounded),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 2,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Tap map:',
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Start'),
                  selected: _active == _End.origin,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) => setState(() => _active = _End.origin),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Destination'),
                  selected: _active == _End.destination,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) => setState(() => _active = _End.destination),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Swap start and destination',
                  visualDensity: VisualDensity.compact,
                  onPressed: (_origin != null || _destination != null)
                      ? _swapEnds
                      : null,
                  icon: const Icon(Icons.swap_vert_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Collapse route panel',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _routePanelCollapsed = true),
                  icon: const Icon(Icons.expand_less_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
            Center(
              child: Material(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: TransportModeSelector(
                    selected: _travel,
                    compact: true,
                    onChanged: (mode) {
                      setState(() => _travel = mode);
                      _scheduleRoute();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
                        onCameraMove: (pos) {
                          _cameraPosition = pos;
                          if ((pos.bearing - _bearing).abs() > 0.5) {
                            setState(() => _bearing = pos.bearing);
                          }
                        },
                        onTap: (latLng) =>
                            _place(GeoPoint(latLng.latitude, latLng.longitude)),
                        mapType: _mapType,
                        style: _isDarkMap ? kDarkMapStyle : null,
                        trafficEnabled: _trafficEnabled,
                        markers: _markers,
                        polylines: _polylines,
                        circles: _circles,
                        myLocationEnabled: _current != null,
                        myLocationButtonEnabled: false,
                        compassEnabled: false,
                        zoomControlsEnabled: false,
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
                              Align(
                                alignment: Alignment.centerLeft,
                                child: SegmentedButton<_PickMode>(
                                  showSelectedIcon: false,
                                  style: SegmentedButton.styleFrom(
                                    backgroundColor: cs.surface.withValues(
                                      alpha: 0.94,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  segments: const [
                                    ButtonSegment(
                                      value: _PickMode.pin,
                                      icon: Icon(Icons.place_rounded, size: 18),
                                      label: Text('Pin'),
                                    ),
                                    ButtonSegment(
                                      value: _PickMode.route,
                                      icon: Icon(
                                        Icons.alt_route_rounded,
                                        size: 18,
                                      ),
                                      label: Text('Route'),
                                    ),
                                  ],
                                  selected: {_mode},
                                  onSelectionChanged: (s) =>
                                      setState(() => _mode = s.first),
                                ),
                              ),
                            if (_searchEnabled) ...[
                              if (widget.allowRoute) const SizedBox(height: 8),
                              _buildSearch(cs),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: MapOverlayControls(
                          bearing: _bearing,
                          onResetBearing: () =>
                              unawaited(resetMapBearing(_map, _cameraPosition)),
                          mapType: _mapType,
                          onMapTypeChanged: (t) =>
                              setState(() => _mapType = t),
                          isDarkMap: _isDarkMap,
                          onDarkMapChanged: (v) {
                            setState(() => _isDarkMap = v);
                            unawaited(_rebuildEtaCalloutIcons());
                          },
                          trafficEnabled: _trafficEnabled,
                          onTrafficChanged: (v) =>
                              setState(() => _trafficEnabled = v),
                          onLocateMe: () => _locateMe(
                            moveCamera: _mode == _PickMode.route,
                          ),
                          locateTooltip: _mode == _PickMode.route
                              ? 'Center on my location'
                              : 'Use my location',
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: cs.surfaceContainerLow,
                  elevation: 2,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _error ?? _hint,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: _error == null
                                      ? cs.onSurfaceVariant
                                      : cs.error,
                                  fontWeight: _error == null
                                      ? FontWeight.w500
                                      : FontWeight.w600,
                                ),
                          ),
                          if (widget.showRadius) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.radar_rounded,
                                  size: 18,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Radius',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                Expanded(
                                  child: Slider(
                                    min: 100,
                                    max: 1000,
                                    divisions: 18,
                                    value: _radius,
                                    label: '${_radius.round()} m',
                                    onChanged: (v) =>
                                        setState(() => _radius = v),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${_radius.round()} m',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: cs.onPrimaryContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (_mode == _PickMode.route && _routes.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _routes.length == 1
                                  ? Align(
                                      alignment: Alignment.centerLeft,
                                      child: RouteSummaryChip(
                                        mode: _travel,
                                        distanceMeters:
                                            _route!.distanceMeters ?? 0,
                                        durationSeconds:
                                            _route!.durationSeconds,
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (
                                            var i = 0;
                                            i < _routes.length;
                                            i++
                                          ) ...[
                                            ChoiceChip(
                                              selected:
                                                  i == _selectedRouteIndex,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              label: Text(
                                                [
                                                  if (_routes[i]
                                                          .durationSeconds !=
                                                      null)
                                                    RouteSummaryChip
                                                        .formatDuration(
                                                      _routes[i]
                                                          .durationSeconds!,
                                                    ),
                                                  if (_routes[i]
                                                          .distanceMeters !=
                                                      null)
                                                    RouteSummaryChip
                                                        .formatDistance(
                                                      _routes[i]
                                                          .distanceMeters!,
                                                    ),
                                                  if (i != _selectedRouteIndex)
                                                    _etaDiffLabel(i),
                                                ].join(' · '),
                                              ),
                                              onSelected: (_) =>
                                                  _selectRoute(i),
                                            ),
                                            if (i < _routes.length - 1)
                                              const SizedBox(width: 6),
                                          ],
                                        ],
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
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _labelController,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    labelText: widget.requireLabel
                                        ? 'Place name'
                                        : 'Label (optional)',
                                    filled: true,
                                    fillColor: cs.surfaceContainerHigh,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                ),
                                onPressed: _canConfirm ? _confirm : null,
                                icon: _loadingRoute
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded, size: 18),
                                label: Text(widget.confirmLabel),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
