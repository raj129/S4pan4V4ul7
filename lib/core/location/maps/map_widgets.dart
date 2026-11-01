import 'dart:async';

import 'package:flutter/material.dart';

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

/// Drive / Walk / Cycle picker.
class TransportModeSelector extends StatelessWidget {
  const TransportModeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final TravelProfile selected;
  final ValueChanged<TravelProfile> onChanged;

  static IconData iconFor(TravelProfile p) => switch (p) {
    TravelProfile.drive => Icons.directions_car_rounded,
    TravelProfile.walk => Icons.directions_walk_rounded,
    TravelProfile.cycle => Icons.directions_bike_rounded,
  };

  @override
  Widget build(BuildContext context) {
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
