import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/services/arrival_alert_service.dart';
import '../../application/services/saved_places_service.dart';
import '../../domain/entities/arrival_alert.dart';
import '../../domain/entities/geo_share.dart';
import '../../domain/entities/saved_place.dart';
import '../widgets/arrival_permissions.dart';
import '../widgets/arrival_place_sheets.dart';

/// Lists the user's saved places, which can be acted on from here, and the
/// places that will notify the chat partner on arrival.
class ArrivalAlertsScreen extends StatefulWidget {
  const ArrivalAlertsScreen({
    super.key,
    required this.service,
    required this.places,
    required this.ownerUid,
    required this.threadId,
    required this.recipientUid,
    required this.recipientName,
    this.onSendShare,
    this.startByAdding = false,
  });

  final ArrivalAlertService service;
  final SavedPlacesService places;
  final String ownerUid;
  final String threadId;
  final String recipientUid;
  final String recipientName;

  /// Posts a pin to this chat. Enables "Send now" on a place.
  final Future<void> Function(GeoShare share)? onSendShare;

  /// Opens the place picker straight away, used by the `/arrive` command.
  final bool startByAdding;

  @override
  State<ArrivalAlertsScreen> createState() => _ArrivalAlertsScreenState();
}

class _ArrivalAlertsScreenState extends State<ArrivalAlertsScreen> {
  StreamSubscription<List<ArrivalAlert>>? _alertsSub;
  StreamSubscription<List<SavedPlace>>? _placesSub;
  List<ArrivalAlert> _alerts = const [];
  List<SavedPlace> _places = const [];

  @override
  void initState() {
    super.initState();
    _alertsSub = widget.service.changes.listen((_) => _refresh());
    _placesSub = widget.places.changes.listen((_) => unawaited(_loadPlaces()));
    unawaited(_loadPlaces());
    unawaited(
      widget.service.restore().then((_) {
        _refresh();
        if (widget.startByAdding && mounted) unawaited(_add());
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_alertsSub?.cancel());
    unawaited(_placesSub?.cancel());
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(
      () =>
          _alerts = widget.service.alertsFor(widget.ownerUid, widget.threadId),
    );
  }

  Future<void> _loadPlaces() async {
    final places = await widget.places.placesFor(widget.ownerUid);
    if (mounted) setState(() => _places = places);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool _isArmedFor(SavedPlace place) =>
      _alerts.any((a) => a.isArmed && a.placeId == place.id);

  /// Arms an alert for [place] to notify the chat partner on arrival.
  Future<void> _tellOnArrival(SavedPlace place) async {
    if (!await ensureArrivalPermissions(context) || !mounted) return;
    if (_isArmedFor(place)) {
      _snack('${place.label} is already armed for ${widget.recipientName}.');
      return;
    }
    await widget.service.add(
      ownerUid: widget.ownerUid,
      threadId: widget.threadId,
      recipientUid: widget.recipientUid,
      label: place.label,
      point: place.point,
      radiusMeters: place.radiusMeters,
      placeId: place.id,
    );
    _snack(
      '${widget.recipientName} will be told when you reach ${place.label}.',
    );
  }

  Future<void> _sendNow(SavedPlace place) async {
    final send = widget.onSendShare;
    if (send == null) return;
    await send(GeoShare.pin(point: place.point, label: place.label));
    _snack('Sent ${place.label}.');
  }

  Future<void> _add() async {
    if (!await ensureArrivalPermissions(context) || !mounted) return;
    final place = await addSavedPlace(
      context,
      places: widget.places,
      ownerUid: widget.ownerUid,
      existing: _places,
      keepByDefault: false,
    );
    if (place == null || !mounted) return;
    await _tellOnArrival(place);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Arrival alerts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('New place'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('My places', style: textTheme.titleSmall),
          ),
          if (_places.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('No saved places yet. Add one with "New place".'),
            ),
          for (final place in _places)
            ListTile(
              leading: CircleAvatar(
                radius: 10,
                backgroundColor: Color(place.tagColor ?? 0xFF757575),
              ),
              title: Text(place.label),
              subtitle: Text(
                '${place.tagName ?? 'No tag'} - ${place.radiusMeters.round()} m'
                '${_isArmedFor(place) ? ' - armed' : ''}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'send':
                      unawaited(_sendNow(place));
                    case 'arrive':
                      unawaited(_tellOnArrival(place));
                    case 'edit':
                      unawaited(
                        editSavedPlace(
                          context,
                          places: widget.places,
                          place: place,
                          others: [
                            for (final p in _places)
                              if (p.id != place.id) p,
                          ],
                        ),
                      );
                    case 'delete':
                      unawaited(widget.places.remove(place.id));
                  }
                },
                itemBuilder: (_) => [
                  if (widget.onSendShare != null)
                    const PopupMenuItem(value: 'send', child: Text('Send now')),
                  const PopupMenuItem(
                    value: 'arrive',
                    child: Text('Tell on arrival'),
                  ),
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Armed alerts', style: textTheme.titleSmall),
          ),
          if (_alerts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'When you reach a place, ${widget.recipientName} is told '
                'automatically.',
              ),
            ),
          for (final alert in _alerts)
            ListTile(
              leading: Icon(
                alert.isArmed
                    ? Icons.notifications_active_rounded
                    : Icons.check_circle_rounded,
                color: alert.isArmed ? cs.primary : cs.tertiary,
              ),
              title: Text(alert.label),
              subtitle: Text(
                alert.isArmed
                    ? (widget.service.fenceError != null
                          ? 'Not active: ${widget.service.fenceError}'
                          : 'Will notify ${widget.recipientName} within '
                                '${alert.radiusMeters.round()} m')
                    : 'Reached - ${widget.recipientName} was notified',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!alert.isArmed)
                    IconButton(
                      tooltip: 'Arm again',
                      icon: const Icon(Icons.replay_rounded),
                      onPressed: () => widget.service.rearm(alert.id),
                    ),
                  IconButton(
                    tooltip: 'Cancel alert',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => widget.service.remove(alert.id),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
