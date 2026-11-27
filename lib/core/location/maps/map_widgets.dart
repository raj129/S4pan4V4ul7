import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../geo_fix.dart';
import '../mock/sim_route.dart';

/// A place returned by a search, independent of any particular API.
class PlaceHit {
  const PlaceHit({
    required this.name,
    required this.address,
    required this.coord,
  });

  final String name;
  final String address;
  final GeoCoord coord;
}

typedef PlaceSearcher = Future<List<PlaceHit>> Function(String query);

final _coordinatePattern = RegExp(
  r'^\s*(-?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)\s*$',
);

/// Reads "12.97, 77.59" style input; null when [query] is not coordinates.
GeoCoord? parseCoordinateQuery(String query) {
  final m = _coordinatePattern.firstMatch(query);
  if (m == null) return null;
  final lat = double.parse(m.group(1)!);
  final lng = double.parse(m.group(2)!);
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  return GeoCoord(lat, lng);
}

/// A search box with a result list. Used wherever the user picks a place.
///
/// Searches on submit (and after a short pause while typing). Choosing a
/// result calls [onSelected]; the field then shows the place name.
class PlaceSearchField extends StatefulWidget {
  const PlaceSearchField({
    super.key,
    required this.search,
    required this.onSelected,
    this.label,
    this.hint = 'Search places',
    this.icon = Icons.search_rounded,
    this.iconColor,
    this.controller,
    this.focusNode,
    this.onLocateMe,
    this.onFocused,
    this.highlighted = false,
    this.enabled = true,
    this.disabledMessage,
  });

  final PlaceSearcher search;
  final ValueChanged<PlaceHit> onSelected;
  final String? label;
  final String hint;
  final IconData icon;
  final Color? iconColor;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Adds a "use my location" button.
  final VoidCallback? onLocateMe;
  final VoidCallback? onFocused;

  /// Outlines the field, e.g. to show it is the target of the next map tap.
  final bool highlighted;

  /// False when search can't work, e.g. no API key; shows [disabledMessage].
  final bool enabled;
  final String? disabledMessage;

  @override
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  Timer? _debounce;
  List<PlaceHit> _results = const [];
  bool _searching = false;
  String? _error;
  int _generation = 0;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) widget.onFocused?.call();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (widget.controller == null) _controller.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), _run);
  }

  Future<void> _run() async {
    final query = _controller.text.trim();
    if (query.isEmpty || query == _lastQuery && _error == null) return;
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.search(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _lastQuery = query;
        _results = results;
        _error = results.isEmpty ? 'No places found.' : null;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _results = const [];
          _error = e.toString();
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  void _select(PlaceHit hit) {
    _generation++;
    _debounce?.cancel();
    _controller.text = hit.name;
    _lastQuery = hit.name;
    _focus.unfocus();
    setState(() => _results = const []);
    widget.onSelected(hit);
  }

  void _clear() {
    _generation++;
    _controller.clear();
    _lastQuery = '';
    setState(() {
      _results = const [];
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!widget.enabled) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(
          widget.disabledMessage ?? 'Search is unavailable.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _run(),
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            isDense: true,
            filled: true,
            fillColor: cs.surface,
            border: OutlineInputBorder(
              borderSide: widget.highlighted
                  ? BorderSide(color: cs.primary, width: 2)
                  : const BorderSide(),
            ),
            enabledBorder: widget.highlighted
                ? OutlineInputBorder(
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  )
                : null,
            prefixIcon: Icon(widget.icon, color: widget.iconColor),
            suffixIconConstraints: const BoxConstraints(minHeight: 40),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_controller.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _clear,
                  ),
                if (widget.onLocateMe != null)
                  IconButton(
                    tooltip: 'Use my location',
                    icon: const Icon(Icons.my_location_rounded),
                    onPressed: widget.onLocateMe,
                  ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(
              _error!,
              style: TextStyle(color: cs.error, fontSize: 12),
            ),
          ),
        if (_results.isNotEmpty)
          Material(
            color: cs.surface,
            elevation: 2,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final r in _results)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(r.name, maxLines: 1),
                      subtitle: Text(
                        r.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _select(r),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Drive / Walk / Cycle / 2-Wheeler / Transit picker.
class TransportModeSelector extends StatelessWidget {
  const TransportModeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  final TravelProfile selected;
  final ValueChanged<TravelProfile> onChanged;
  final bool compact;

  static IconData iconFor(TravelProfile p) => switch (p) {
    TravelProfile.drive => Icons.directions_car_rounded,
    TravelProfile.twoWheeler => Icons.two_wheeler_rounded,
    TravelProfile.walk => Icons.directions_walk_rounded,
    TravelProfile.cycle => Icons.directions_bike_rounded,
    TravelProfile.transit => Icons.directions_transit_rounded,
  };

  @override
  Widget build(BuildContext context) {
    if (compact) {
      final cs = Theme.of(context).colorScheme;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in TravelProfile.values)
            Tooltip(
              message: p.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onChanged(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: p == selected
                        ? cs.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    iconFor(p),
                    size: 18,
                    color: p == selected
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return SegmentedButton<TravelProfile>(
      showSelectedIcon: false,
      segments: [
        for (final p in TravelProfile.values)
          ButtonSegment(value: p, icon: Icon(iconFor(p)), label: Text(p.label)),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// "12.3 km · 24 min" style summary of a planned route.
class RouteSummaryChip extends StatelessWidget {
  const RouteSummaryChip({
    super.key,
    required this.mode,
    required this.distanceMeters,
    this.durationSeconds,
    this.note,
  });

  final TravelProfile mode;
  final double distanceMeters;
  final int? durationSeconds;
  final String? note;

  static String formatDistance(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';

  static String formatDuration(int seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '${minutes < 1 ? 1 : minutes} min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parts = [
      formatDistance(distanceMeters),
      ?(durationSeconds == null ? null : formatDuration(durationSeconds!)),
      ?note,
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              TransportModeSelector.iconFor(mode),
              size: 18,
              color: cs.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                parts.join(' · '),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resets a [GoogleMap] camera to north-up (`bearing: 0`, `tilt: 0`) while
/// preserving its current target and zoom.
Future<void> resetMapBearing(
  GoogleMapController? controller,
  CameraPosition? currentCamera,
) async {
  if (controller == null || currentCamera == null) return;
  await controller.animateCamera(
    CameraUpdate.newCameraPosition(
      CameraPosition(
        target: currentCamera.target,
        zoom: currentCamera.zoom,
        bearing: 0,
        tilt: 0,
      ),
    ),
  );
}

/// Official Google Maps Night/Dark style that keeps roads crisp and preserves
/// native multi-colored metro/transit lines and station icons.
const String kDarkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#242f3e"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#263c3f"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#6b9a76"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212a37"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#746855"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1f2835"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f3d19c"}]},
  {"featureType":"transit","stylers":[{"visibility":"on"}]},
  {"featureType":"transit.line","stylers":[{"visibility":"on"}]},
  {"featureType":"transit.station","stylers":[{"visibility":"on"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
  {"featureType":"transit.station","elementType":"labels.icon","stylers":[{"visibility":"on"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]},
  {"featureType":"water","elementType":"labels.text.stroke","stylers":[{"color":"#17263c"}]}
]
''';

/// Compact vertical pill of map controls: orientation/compass reset,
/// Street / Satellite / Terrain switcher, Dark/Light theme, Traffic, and
/// optional re-center button.
class MapOverlayControls extends StatelessWidget {
  const MapOverlayControls({
    super.key,
    required this.bearing,
    required this.onResetBearing,
    required this.mapType,
    required this.onMapTypeChanged,
    this.isDarkMap = false,
    this.onDarkMapChanged,
    this.trafficEnabled = false,
    this.onTrafficChanged,
    this.onLocateMe,
    this.locateTooltip = 'Re-center',
    this.locateIcon = Icons.my_location_rounded,
  });

  final double bearing;
  final VoidCallback onResetBearing;
  final MapType mapType;
  final ValueChanged<MapType> onMapTypeChanged;
  final bool isDarkMap;
  final ValueChanged<bool>? onDarkMapChanged;
  final bool trafficEnabled;
  final ValueChanged<bool>? onTrafficChanged;
  final VoidCallback? onLocateMe;
  final String locateTooltip;
  final IconData locateIcon;

  bool get _isSatellite =>
      mapType == MapType.satellite || mapType == MapType.hybrid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rotated = bearing.abs() > 1.0 && (360 - bearing.abs()) > 1.0;

    return Material(
      color: cs.surfaceContainerHigh.withValues(alpha: 0.94),
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: rotated ? 'Reset orientation to North' : 'Orientation: North',
            onPressed: onResetBearing,
            icon: Transform.rotate(
              angle: -bearing * math.pi / 180,
              child: Icon(
                Icons.explore_rounded,
                color: rotated ? cs.primary : cs.onSurface,
              ),
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            indent: 8,
            endIndent: 8,
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
          PopupMenuButton<MapType>(
            tooltip: _isSatellite ? 'Map view: Satellite' : 'Map view: Street',
            initialValue: mapType,
            onSelected: onMapTypeChanged,
            icon: Icon(
              _isSatellite
                  ? Icons.satellite_alt_rounded
                  : mapType == MapType.terrain
                  ? Icons.terrain_rounded
                  : Icons.map_outlined,
              color: _isSatellite ? cs.primary : cs.onSurface,
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: MapType.normal,
                child: Row(
                  children: [
                    Icon(
                      Icons.map_outlined,
                      size: 20,
                      color: mapType == MapType.normal ? cs.primary : null,
                    ),
                    const SizedBox(width: 12),
                    const Text('Street map'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: MapType.hybrid,
                child: Row(
                  children: [
                    Icon(
                      Icons.satellite_alt_rounded,
                      size: 20,
                      color: _isSatellite ? cs.primary : null,
                    ),
                    const SizedBox(width: 12),
                    const Text('Satellite'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: MapType.terrain,
                child: Row(
                  children: [
                    Icon(
                      Icons.terrain_rounded,
                      size: 20,
                      color: mapType == MapType.terrain ? cs.primary : null,
                    ),
                    const SizedBox(width: 12),
                    const Text('Terrain'),
                  ],
                ),
              ),
            ],
          ),
          if (onDarkMapChanged != null) ...[
            Divider(
              height: 1,
              thickness: 1,
              indent: 8,
              endIndent: 8,
              color: cs.outlineVariant.withValues(alpha: 0.4),
            ),
            IconButton(
              tooltip: isDarkMap ? 'Light map theme' : 'Dark map theme',
              onPressed: () => onDarkMapChanged!(!isDarkMap),
              icon: Icon(
                isDarkMap ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                color: isDarkMap ? cs.primary : cs.onSurface,
              ),
            ),
          ],
          if (onTrafficChanged != null) ...[
            Divider(
              height: 1,
              thickness: 1,
              indent: 8,
              endIndent: 8,
              color: cs.outlineVariant.withValues(alpha: 0.4),
            ),
            IconButton(
              tooltip: trafficEnabled ? 'Hide live traffic' : 'Show live traffic',
              onPressed: () => onTrafficChanged!(!trafficEnabled),
              icon: Icon(
                Icons.traffic_rounded,
                color: trafficEnabled ? cs.primary : cs.onSurface,
              ),
            ),
          ],
          if (onLocateMe != null) ...[
            Divider(
              height: 1,
              thickness: 1,
              indent: 8,
              endIndent: 8,
              color: cs.outlineVariant.withValues(alpha: 0.4),
            ),
            IconButton(
              tooltip: locateTooltip,
              onPressed: onLocateMe,
              icon: Icon(locateIcon, color: cs.onSurface),
            ),
          ],
        ],
      ),
    );
  }
}

