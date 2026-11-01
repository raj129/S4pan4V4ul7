import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../features/chat/application/services/place_search_service.dart';
import '../../../features/chat/domain/entities/geo_share.dart' show GeoPoint;
import '../../../features/vault/domain/repositories/settings_repository.dart';
import '../../widgets/app_surfaces.dart';
import '../app_location.dart';
import '../geo_fix.dart';
import '../maps/map_widgets.dart';
import '../mock/mock_location_controller.dart';
import '../mock/mock_location_preferences.dart';
import '../mock/route_simulator.dart';
import '../mock/sim_route.dart';
import '../mock/system_mock_bridge.dart';
import '../mock/traffic_route_service.dart';

enum _MapTarget { fixed, origin, destination }

/// Screen for faking the device location: a fixed point, or a traffic-aware
/// simulated trip between two points chosen by search or on the map.
class DeveloperOptionsScreen extends StatefulWidget {
  const DeveloperOptionsScreen({
    super.key,
    required this.location,
    required this.routes,
    required this.settingsRepository,
    this.places,
    this.showMap,
  });

  final AppLocation location;
  final TrafficRouteService routes;
  final SettingsRepository settingsRepository;

  /// Place search; defaults to the shared Google-backed service.
  final PlaceSearchService? places;

  /// Defaults to mobile platforms, where Google Maps is available.
  final bool? showMap;

  @override
  State<DeveloperOptionsScreen> createState() => _DeveloperOptionsScreenState();
}

class _DeveloperOptionsScreenState extends State<DeveloperOptionsScreen>
    with WidgetsBindingObserver {
  MockLocationController get _mock => widget.location.mock;

  late final PlaceSearchService _places = widget.places ?? PlaceSearchService();
  MockLocationPreferences _prefs = const MockLocationPreferences();
  MockMode _editing = MockMode.fixed;
  _MapTarget _target = _MapTarget.fixed;
  SimRoute? _preview;
  bool _fetching = false;
  bool _loaded = false;
  bool _searchReady = true;
  GoogleMapController? _map;
  SystemMockAvailability? _systemAvailability;
  Timer? _autoPreview;
  int _routeGeneration = 0;

  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _searchFixed = TextEditingController();
  final _searchA = TextEditingController();
  final _searchB = TextEditingController();

  bool get _showMap => widget.showMap ?? (Platform.isAndroid || Platform.isIOS);

  static const _searchDisabledMessage =
      'Place search needs a Google Maps key in this build. Tap the map or '
      'type "lat, lng" instead.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mock.addListener(_onMockChanged);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(
      _mock.systemBridge.availability().then((a) {
        if (mounted) setState(() => _systemAvailability = a);
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mock.removeListener(_onMockChanged);
    _autoPreview?.cancel();
    _lat.dispose();
    _lng.dispose();
    _searchFixed.dispose();
    _searchA.dispose();
    _searchB.dispose();
    _map?.dispose();
    super.dispose();
  }

  void _onMockChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final raw = await widget.settingsRepository.getMockLocationPrefs();
    final availability = await _mock.systemBridge.availability();
    final searchReady = await _places.isConfigured;
    if (!mounted) return;
    final prefs = MockLocationPreferences.decode(raw);
    setState(() {
      _prefs = prefs;
      _systemAvailability = availability;
      _searchReady = searchReady;
      _loaded = true;
      _searchA.text = prefs.routeOrigin?.toString() ?? '';
      _searchB.text = prefs.routeDestination?.toString() ?? '';
      _searchFixed.text = prefs.fixedPoint?.toString() ?? '';
      if (_mock.mode == MockMode.route) {
        _editing = MockMode.route;
        _target = _MapTarget.origin;
        _preview = _mock.simulator?.route;
      }
    });
    _syncFixedFields();
  }

  void _syncFixedFields() {
    final p = _prefs.fixedPoint;
    _lat.text = p == null ? '' : p.latitude.toStringAsFixed(6);
    _lng.text = p == null ? '' : p.longitude.toStringAsFixed(6);
  }

  Future<void> _save(MockLocationPreferences next) async {
    setState(() => _prefs = next);
    await widget.settingsRepository.setMockLocationPrefs(next.encode());
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------- picking

  TextEditingController _fieldFor(_MapTarget t) => switch (t) {
    _MapTarget.fixed => _searchFixed,
    _MapTarget.origin => _searchA,
    _MapTarget.destination => _searchB,
  };

  /// Sets the point for [target], by map tap, search result or real GPS.
  Future<void> _setPoint(
    _MapTarget target,
    GeoCoord point, {
    String? text,
  }) async {
    _fieldFor(target).text = text ?? point.toString();
    switch (target) {
      case _MapTarget.fixed:
        await _save(_prefs.copyWith(fixedPoint: point));
        _syncFixedFields();
      case _MapTarget.origin:
        await _save(_prefs.copyWith(routeOrigin: point));
      case _MapTarget.destination:
        await _save(_prefs.copyWith(routeDestination: point));
    }
    if (target != _MapTarget.fixed) _scheduleAutoPreview();
  }

  Future<void> _onMapTap(LatLng latLng) async {
    final point = GeoCoord(latLng.latitude, latLng.longitude);
    final tapped = _target;
    await _setPoint(tapped, point);
    if (tapped == _MapTarget.origin && mounted) {
      setState(() => _target = _MapTarget.destination);
    }
  }

  Future<List<PlaceHit>> _search(String query) async {
    final coord = parseCoordinateQuery(query);
    if (coord != null) {
      return [
        PlaceHit(name: coord.toString(), address: 'Coordinates', coord: coord),
      ];
    }
    if (!_searchReady) throw PlaceSearchException(_searchDisabledMessage);
    final near = _prefs.routeOrigin ?? _prefs.fixedPoint ?? _mock.latest?.coord;
    final results = await _places.search(
      query,
      near: near == null ? null : GeoPoint(near.latitude, near.longitude),
    );
    return [
      for (final r in results)
        PlaceHit(
          name: r.name,
          address: r.address,
          coord: GeoCoord(r.point.latitude, r.point.longitude),
        ),
    ];
  }

  Future<void> _onPlaceSelected(_MapTarget target, PlaceHit hit) async {
    await _setPoint(target, hit.coord, text: hit.name);
    await _moveCamera(hit.coord);
    if (target == _MapTarget.origin && mounted) {
      setState(() => _target = _MapTarget.destination);
    }
  }

  Future<void> _applyTypedFixedPoint() async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      _toast('Enter a valid latitude (−90…90) and longitude (−180…180).');
      return;
    }
    final point = GeoCoord(lat, lng);
    await _setPoint(_MapTarget.fixed, point);
    await _moveCamera(point);
  }

  Future<GeoCoord?> _realPosition() async {
    try {
      final fix = await widget.location.real.current(
        timeLimit: const Duration(seconds: 15),
      );
      return fix.coord;
    } catch (e) {
      _toast('Could not read the real GPS: $e');
      return null;
    }
  }

  Future<void> _useRealPositionFor(_MapTarget target) async {
    final point = await _realPosition();
    if (point == null || !mounted) return;
    await _setPoint(target, point, text: 'My location');
    await _moveCamera(point);
  }

  Future<void> _moveCamera(GeoCoord point) async {
    await _map?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(point.latitude, point.longitude), 15),
    );
  }

  Future<void> _swapEnds() async {
    final a = _prefs.routeOrigin;
    final b = _prefs.routeDestination;
    final textA = _searchA.text;
    _searchA.text = _searchB.text;
    _searchB.text = textA;
    await _save(
      MockLocationPreferences(
        fixedPoint: _prefs.fixedPoint,
        fixedAccuracy: _prefs.fixedAccuracy,
        routeOrigin: b,
        routeDestination: a,
        profile: _prefs.profile,
        baseSpeedKmh: _prefs.baseSpeedKmh,
        multiplier: _prefs.multiplier,
        loop: _prefs.loop,
        followTraffic: _prefs.followTraffic,
        trafficRefreshMinutes: _prefs.trafficRefreshMinutes,
        systemWide: _prefs.systemWide,
      ),
    );
    _scheduleAutoPreview();
  }

  /// Recomputes the route shortly after A, B or the mode changes, like a
  /// maps app. A running simulation keeps its own route.
  void _scheduleAutoPreview() {
    if (!mounted) return;
    _autoPreview?.cancel();
    _routeGeneration++;
    setState(() => _preview = null);
    if (_prefs.routeOrigin == null || _prefs.routeDestination == null) return;
    if (_mock.mode == MockMode.route) return;
    _autoPreview = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_fetchRoute(quiet: true)),
    );
  }

  // ---------------------------------------------------------------- actions

  Future<void> _startFixed() async {
    final point = _prefs.fixedPoint;
    if (point == null) {
      _toast('Pick a point on the map or type coordinates first.');
      return;
    }
    _mock.enableFixed(point, accuracy: _prefs.fixedAccuracy);
    await _applySystemWidePreference();
    _toast('Mock location set. Every location in the app now uses it.');
  }

  Future<SimRoute?> _fetchRoute({bool quiet = false}) async {
    final a = _prefs.routeOrigin;
    final b = _prefs.routeDestination;
    if (a == null || b == null) {
      if (!quiet) _toast('Set both start (A) and destination (B).');
      return null;
    }
    final generation = ++_routeGeneration;
    setState(() => _fetching = true);
    try {
      final route = await widget.routes.fetch(
        origin: a,
        destination: b,
        profile: _prefs.profile,
      );
      if (!mounted || generation != _routeGeneration) return null;
      setState(() => _preview = route);
      if (!quiet && route.warning != null) _toast(route.warning!);
      unawaited(_fitRoute(route));
      return route;
    } catch (e) {
      if (!quiet) _toast('Route failed: $e');
      return null;
    } finally {
      if (mounted && generation == _routeGeneration) {
        setState(() => _fetching = false);
      }
    }
  }

  Future<void> _fitRoute(SimRoute route) async {
    final map = _map;
    if (map == null || route.points.length < 2) return;
    var s = route.points.first.latitude, n = s;
    var w = route.points.first.longitude, e = w;
    for (final p in route.points) {
      if (p.latitude < s) s = p.latitude;
      if (p.latitude > n) n = p.latitude;
      if (p.longitude < w) w = p.longitude;
      if (p.longitude > e) e = p.longitude;
    }
    await map.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e)),
        48,
      ),
    );
  }

  Future<void> _startRoute() async {
    final route = _preview ?? await _fetchRoute();
    if (route == null || !mounted) return;
    final destination = _prefs.routeDestination!;
    final profile = _prefs.profile;
    _mock.startRoute(
      route,
      _prefs.toSimulationConfig(),
      refresher: route.source == SimRouteSource.straightLine
          ? null
          : (from) => widget.routes.fetch(
              origin: from,
              destination: destination,
              profile: profile,
            ),
    );
    await _applySystemWidePreference();
    _toast('Simulation started.');
  }

  Future<void> _applySystemWidePreference() async {
    if (_prefs.systemWide && !_mock.systemWideRunning) {
      await _mock.setSystemWide(true);
      final error = _mock.systemWideError;
      if (error != null) _toast(error);
    }
  }

  Future<void> _setSystemWide(bool enabled) async {
    await _save(_prefs.copyWith(systemWide: enabled));
    await _mock.setSystemWide(enabled);
    final error = _mock.systemWideError;
    if (error != null) {
      await _save(_prefs.copyWith(systemWide: false));
      _toast(error);
    }
    final availability = await _mock.systemBridge.availability();
    if (mounted) setState(() => _systemAvailability = availability);
  }

  Future<void> _updateSimConfig(MockLocationPreferences next) async {
    await _save(next);
    _mock.updateSimulationConfig(next.toSimulationConfig());
  }

  Future<void> _useRealGps() async {
    await _mock.useRealGps();
    _toast('Back on the real GPS.');
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mock location')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _statusCard(context),
                const SectionHeader('Mock location'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<MockMode>(
                    segments: const [
                      ButtonSegment(
                        value: MockMode.fixed,
                        icon: Icon(Icons.place_outlined),
                        label: Text('Fixed point'),
                      ),
                      ButtonSegment(
                        value: MockMode.route,
                        icon: Icon(Icons.route_outlined),
                        label: Text('Route A → B'),
                      ),
                    ],
                    selected: {_editing},
                    onSelectionChanged: (s) => setState(() {
                      _editing = s.first;
                      _target = _editing == MockMode.fixed
                          ? _MapTarget.fixed
                          : _MapTarget.origin;
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                if (_showMap) _mapView(context),
                if (_editing == MockMode.fixed)
                  ..._fixedSection(context)
                else
                  ..._routeSection(context),
                const SectionHeader('Other apps'),
                _systemWideCard(context),
              ],
            ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final active = _mock.isActive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: InfoBanner(
        tone: active ? InfoBannerTone.warning : InfoBannerTone.success,
        title: active ? 'Mock location is ON' : 'Using real GPS',
        message: active
            ? '${_mock.statusLabel}\nChats, maps and live location in this '
                  'app see the simulated position'
                  '${_mock.systemWideRunning ? ', and so do other apps' : ''}.'
            : 'Locations come from the device GPS. Choose a fixed point or a '
                  'route below to simulate one.',
        action: active
            ? FilledButton.tonalIcon(
                key: const Key('dev-use-real-gps'),
                onPressed: _useRealGps,
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Use real GPS'),
              )
            : null,
      ),
    );
  }

  Widget _mapView(BuildContext context) {
    final start =
        _mock.latest?.coord ??
        _prefs.fixedPoint ??
        _prefs.routeOrigin ??
        const GeoCoord(20, 0);
    final zoomed =
        _mock.latest != null ||
        _prefs.fixedPoint != null ||
        _prefs.routeOrigin != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 300,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(start.latitude, start.longitude),
                  zoom: zoomed ? 14 : 2,
                ),
                onMapCreated: (c) => _map = c,
                onTap: _onMapTap,
                markers: _markers(),
                polylines: _polylines(context),
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                trafficEnabled: _editing == MockMode.route,
                gestureRecognizers: {
                  Factory<OneSequenceGestureRecognizer>(
                    EagerGestureRecognizer.new,
                  ),
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            switch (_target) {
              _MapTarget.fixed => 'Tap the map to choose the mock point.',
              _MapTarget.origin => 'Tap the map to set the start (A).',
              _MapTarget.destination =>
                'Tap the map to set the destination (B).',
            },
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Set<Marker> _markers() {
    LatLng ll(GeoCoord c) => LatLng(c.latitude, c.longitude);
    final live = _mock.latest;
    return {
      if (_editing == MockMode.fixed && _prefs.fixedPoint != null)
        Marker(
          markerId: const MarkerId('fixed'),
          position: ll(_prefs.fixedPoint!),
          infoWindow: const InfoWindow(title: 'Mock point'),
        ),
      if (_editing == MockMode.route && _prefs.routeOrigin != null)
        Marker(
          markerId: const MarkerId('a'),
          position: ll(_prefs.routeOrigin!),
          infoWindow: const InfoWindow(title: 'A · start'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      if (_editing == MockMode.route && _prefs.routeDestination != null)
        Marker(
          markerId: const MarkerId('b'),
          position: ll(_prefs.routeDestination!),
          infoWindow: const InfoWindow(title: 'B · destination'),
        ),
      if (live != null)
        Marker(
          markerId: const MarkerId('live'),
          position: ll(live.coord),
          rotation: live.heading,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Mock position'),
        ),
    };
  }

  static Color bandColor(TrafficBand band, ColorScheme cs) => switch (band) {
    TrafficBand.normal => const Color(0xFF2E7D32),
    TrafficBand.slow => const Color(0xFFF9A825),
    TrafficBand.jam => const Color(0xFFC62828),
    TrafficBand.unknown => cs.primary,
  };

  Set<Polyline> _polylines(BuildContext context) {
    final route = _editing == MockMode.route
        ? (_mock.simulator?.route ?? _preview)
        : null;
    if (route == null || route.points.length < 2) return {};
    final cs = Theme.of(context).colorScheme;
    final lines = <Polyline>{};
    var start = 0;
    for (var i = 1; i <= route.segmentBands.length; i++) {
      final ended =
          i == route.segmentBands.length ||
          route.segmentBands[i] != route.segmentBands[start];
      if (!ended) continue;
      lines.add(
        Polyline(
          polylineId: PolylineId('seg$start'),
          color: bandColor(route.segmentBands[start], cs),
          width: 6,
          points: [
            for (var k = start; k <= i; k++)
              LatLng(route.points[k].latitude, route.points[k].longitude),
          ],
        ),
      );
      start = i;
    }
    return lines;
  }

  // ---------------------------------------------------------- fixed point

  List<Widget> _fixedSection(BuildContext context) {
    final running = _mock.mode == MockMode.fixed;
    return [
      const SectionHeader('Fixed point'),
      SettingsCard(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: PlaceSearchField(
              key: const Key('dev-search-fixed'),
              controller: _searchFixed,
              label: 'Place',
              hint: 'Search a place or drop a marker',
              search: _search,
              onSelected: (hit) async {
                await _setPoint(_MapTarget.fixed, hit.coord, text: hit.name);
                await _moveCamera(hit.coord);
              },
              onLocateMe: () => _useRealPositionFor(_MapTarget.fixed),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('dev-fixed-lat'),
                    controller: _lat,
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('dev-fixed-lng'),
                    controller: _lng,
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    onSubmitted: (_) => _applyTypedFixedPoint(),
                  ),
                ),
                IconButton(
                  tooltip: 'Use these coordinates',
                  onPressed: _applyTypedFixedPoint,
                  icon: const Icon(Icons.check_rounded),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.my_location),
            title: const Text('Start from my real location'),
            onTap: () => _useRealPositionFor(_MapTarget.fixed),
          ),
          ListTile(
            leading: const Icon(Icons.adjust),
            title: const Text('Reported accuracy'),
            subtitle: Slider(
              value: _prefs.fixedAccuracy.clamp(1, 100),
              min: 1,
              max: 100,
              divisions: 99,
              label: '${_prefs.fixedAccuracy.round()} m',
              onChanged: (v) =>
                  setState(() => _prefs = _prefs.copyWith(fixedAccuracy: v)),
              onChangeEnd: (v) => _save(_prefs.copyWith(fixedAccuracy: v)),
            ),
            trailing: Text('${_prefs.fixedAccuracy.round()} m'),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: FilledButton.icon(
          key: const Key('dev-start-fixed'),
          onPressed: _startFixed,
          icon: const Icon(Icons.location_on),
          label: Text(running ? 'Update mock point' : 'Use this mock point'),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------- route

  List<Widget> _routeSection(BuildContext context) {
    final sim = _mock.mode == MockMode.route ? _mock.snapshot : null;
    final route = _mock.simulator?.route ?? _preview;
    return [
      const SectionHeader('Route'),
      SettingsCard(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: PlaceSearchField(
              key: const Key('dev-search-a'),
              controller: _searchA,
              label: 'A · start',
              hint: 'Search a place or drop a marker',
              icon: Icons.trip_origin,
              iconColor: Colors.green,
              search: _search,
              highlighted: _target == _MapTarget.origin && _showMap,
              onFocused: () => setState(() => _target = _MapTarget.origin),
              onSelected: (hit) => _onPlaceSelected(_MapTarget.origin, hit),
              onLocateMe: () => _useRealPositionFor(_MapTarget.origin),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: PlaceSearchField(
              key: const Key('dev-search-b'),
              controller: _searchB,
              label: 'B · destination',
              hint: 'Search a place or drop a marker',
              icon: Icons.place,
              iconColor: Colors.red,
              search: _search,
              highlighted: _target == _MapTarget.destination && _showMap,
              onFocused: () => setState(() => _target = _MapTarget.destination),
              onSelected: (hit) =>
                  _onPlaceSelected(_MapTarget.destination, hit),
              onLocateMe: () => _useRealPositionFor(_MapTarget.destination),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: const Text('Swap A and B'),
            enabled:
                _prefs.routeOrigin != null || _prefs.routeDestination != null,
            onTap: _swapEnds,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TransportModeSelector(
              selected: _prefs.profile,
              onChanged: (profile) {
                unawaited(
                  _updateSimConfig(
                    _prefs.copyWith(profile: profile, baseSpeedKmh: 0),
                  ).then((_) => _scheduleAutoPreview()),
                );
              },
            ),
          ),
        ],
      ),
      if (route == null && _fetching)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: LinearProgressIndicator(),
        ),
      if (route != null) _routeSummary(context, route),
      const SectionHeader('Speed'),
      SettingsCard(
        children: [
          ListTile(
            leading: const Icon(Icons.speed),
            title: Text(
              'Cruise speed · '
              '${_prefs.toSimulationConfig().effectiveBaseKmh.round()} km/h',
            ),
            subtitle: Slider(
              value: _prefs.toSimulationConfig().effectiveBaseKmh.clamp(
                1,
                _maxSpeed,
              ),
              min: 1,
              max: _maxSpeed,
              divisions: _maxSpeed.round() - 1,
              onChanged: (v) =>
                  setState(() => _prefs = _prefs.copyWith(baseSpeedKmh: v)),
              onChangeEnd: (v) =>
                  _updateSimConfig(_prefs.copyWith(baseSpeedKmh: v)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Time speed-up'),
                for (final m in const [1.0, 2.0, 5.0, 10.0])
                  ChoiceChip(
                    label: Text('${m.round()}×'),
                    selected: _prefs.multiplier == m,
                    onSelected: (_) =>
                        _updateSimConfig(_prefs.copyWith(multiplier: m)),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.traffic_outlined),
            title: const Text('Follow live traffic'),
            subtitle: Text(
              _prefs.profile.supportsTraffic
                  ? 'Slow down in slow traffic and jams, and refresh traffic '
                        'every ${_prefs.trafficRefreshMinutes} min.'
                  : 'Traffic data is only available when driving.',
            ),
            value: _prefs.followTraffic && _prefs.profile.supportsTraffic,
            onChanged: _prefs.profile.supportsTraffic
                ? (v) => _updateSimConfig(_prefs.copyWith(followTraffic: v))
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.repeat),
            title: const Text('Loop'),
            subtitle: const Text('Start again from A when B is reached.'),
            value: _prefs.loop,
            onChanged: (v) => _updateSimConfig(_prefs.copyWith(loop: v)),
          ),
        ],
      ),
      if (sim != null) _liveStats(context, sim),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _fetching ? null : _fetchRoute,
              icon: _fetching
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.alt_route),
              label: const Text('Recalculate route'),
            ),
            if (sim == null)
              FilledButton.icon(
                key: const Key('dev-start-route'),
                onPressed: _fetching ? null : _startRoute,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start simulation'),
              )
            else ...[
              if (sim.status == SimStatus.running)
                FilledButton.tonalIcon(
                  onPressed: _mock.pauseRoute,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                )
              else if (sim.status == SimStatus.paused)
                FilledButton.icon(
                  onPressed: _mock.resumeRoute,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume'),
                ),
              OutlinedButton.icon(
                onPressed: _mock.restartRoute,
                icon: const Icon(Icons.replay),
                label: const Text('Restart'),
              ),
              TextButton.icon(
                key: const Key('dev-stop-route'),
                onPressed: _mock.useRealGps,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop & use real GPS'),
              ),
              if (_prefs.profile.supportsTraffic)
                OutlinedButton.icon(
                  onPressed: _mock.isRefreshingTraffic
                      ? null
                      : _mock.refreshTrafficNow,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh traffic'),
                ),
              FilledButton.icon(
                onPressed: _fetching ? null : _startRoute,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Start new trip'),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  double get _maxSpeed => switch (_prefs.profile) {
    TravelProfile.walk => 20,
    TravelProfile.cycle => 60,
    TravelProfile.drive => 160,
  };

  Widget _routeSummary(BuildContext context, SimRoute route) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final km = route.totalMeters / 1000;
    final shares = route.bandShares();
    final eta = route.apiDurationSeconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${km.toStringAsFixed(km < 10 ? 2 : 1)} km'
                '${eta == null ? '' : ' · ${_duration(eta.toDouble())} by Google'}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(route.source.label, style: theme.textTheme.bodySmall),
              if (route.warning != null)
                Text(
                  route.warning!,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                ),
              if (route.hasTraffic) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        for (final band in TrafficBand.values)
                          if ((shares[band] ?? 0) > 0)
                            Expanded(
                              flex: ((shares[band] ?? 0) * 1000).round().clamp(
                                1,
                                1000,
                              ),
                              child: ColoredBox(color: bandColor(band, cs)),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final band in TrafficBand.values)
                      if ((shares[band] ?? 0) > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 10,
                              color: bandColor(band, cs),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${band.label} '
                              '${((shares[band] ?? 0) * 100).round()}%',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveStats(BuildContext context, SimSnapshot sim) {
    final theme = Theme.of(context);
    final status = switch (sim.status) {
      SimStatus.running => 'Moving',
      SimStatus.paused => 'Paused',
      SimStatus.finished => 'Arrived at B',
    };
    final refreshError = _mock.trafficRefreshError;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$status · ${(sim.progress * 100).round()}%',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: sim.progress),
              const SizedBox(height: 8),
              Text(
                'Road speed ${sim.roadSpeedKmh.round()} km/h · '
                '${sim.band.label}\n'
                '${((sim.totalMeters - sim.distanceAlong) / 1000).toStringAsFixed(2)} km left · '
                'about ${_duration(sim.remainingSeconds)}',
                style: theme.textTheme.bodySmall,
              ),
              if (_mock.isRefreshingTraffic)
                Text('Refreshing traffic…', style: theme.textTheme.bodySmall),
              if (refreshError != null)
                Text(
                  'Traffic refresh: $refreshError',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _duration(double seconds) {
    final s = seconds.round();
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    if (m < 60) return '$m min';
    return '${m ~/ 60} h ${m % 60} min';
  }

  // ---------------------------------------------------------- system-wide

  Widget _systemWideCard(BuildContext context) {
    final availability = _systemAvailability;
    final unsupported = availability == SystemMockAvailability.unsupported;
    final notSelected = availability == SystemMockAvailability.notSelected;
    return SettingsCard(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.public),
          title: const Text('Mock for all apps'),
          subtitle: Text(
            unsupported
                ? 'Only available on Android.'
                : 'Also feed the mock position to Android, so other apps see '
                      'it. Shows an ongoing notification while active.',
          ),
          value: _prefs.systemWide,
          onChanged: unsupported ? null : _setSystemWide,
        ),
        if (notSelected)
          ListTile(
            leading: const Icon(Icons.settings_applications_outlined),
            title: const Text('Select this app as the mock location app'),
            subtitle: const Text(
              'Android Settings → System → Developer options → Select mock '
              'location app → Calculator. Then come back here.',
            ),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              await _mock.systemBridge.openDeveloperSettings();
            },
          ),
        if (_mock.systemWideRunning)
          const ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('Other apps are receiving the mock position'),
          ),
      ],
    );
  }
}
