import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/services/arrival_alert_service.dart';
import '../../application/services/saved_places_service.dart';
import '../../domain/entities/arrival_alert.dart';
import '../widgets/arrival_place_sheets.dart';
import '../../domain/entities/chat_user.dart';
import '../../domain/entities/geo_share.dart';
import '../../domain/entities/saved_place.dart';
import '../state/thread_list_cubit.dart';
import '../widgets/arrival_permissions.dart';

typedef SendGeoShare =
    Future<void> Function({
      required String threadId,
      required String senderId,
      required String recipientUid,
      required GeoShare share,
    });

/// Standalone place manager, reachable from the chat list without opening a
/// conversation. Places can be sent to any contact on demand, or armed so the
/// contact is told automatically when the user arrives.
class MyLocationsScreen extends StatefulWidget {
  const MyLocationsScreen({
    super.key,
    required this.myUid,
    required this.placesService,
    required this.arrivalService,
    required this.sendGeoShare,
    required this.contacts,
    required this.nameOf,
  });

  final String myUid;
  final SavedPlacesService placesService;
  final ArrivalAlertService arrivalService;
  final SendGeoShare sendGeoShare;

  /// Conversations to choose a recipient from.
  final List<ThreadListItem> Function() contacts;
  final String Function(ChatUser user) nameOf;

  @override
  State<MyLocationsScreen> createState() => _MyLocationsScreenState();
}

class _MyLocationsScreenState extends State<MyLocationsScreen> {
  StreamSubscription<Object>? _placesSub;
  StreamSubscription<Object>? _alertsSub;
  List<SavedPlace> _places = const [];
  List<ArrivalAlert> _alerts = const [];

  @override
  void initState() {
    super.initState();
    _placesSub = widget.placesService.changes.listen((_) => _load());
    _alertsSub = widget.arrivalService.changes.listen((_) => _loadAlerts());
    unawaited(_load());
    unawaited(widget.arrivalService.restore().then((_) => _loadAlerts()));
  }

  @override
  void dispose() {
    unawaited(_placesSub?.cancel());
    unawaited(_alertsSub?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final places = await widget.placesService.placesFor(widget.myUid);
    if (mounted) setState(() => _places = places);
  }

  void _loadAlerts() {
    if (!mounted) return;
    setState(() => _alerts = widget.arrivalService.alertsOwnedBy(widget.myUid));
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addPlace() async {
    await addSavedPlace(
      context,
      places: widget.placesService,
      ownerUid: widget.myUid,
      existing: _places,
    );
  }

  Future<ThreadListItem?> _pickContact(String title) {
    final contacts = widget.contacts();
    if (contacts.isEmpty) {
      _snack('Start a conversation first.');
      return Future.value();
    }
    return showModalBottomSheet<ThreadListItem>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  title,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in contacts)
                      ListTile(
                        leading: const Icon(Icons.person_outline_rounded),
                        title: Text(widget.nameOf(item.otherUser)),
                        onTap: () => Navigator.pop(sheetContext, item),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendNow(SavedPlace place) async {
    final target = await _pickContact('Send "${place.label}" to');
    if (target == null) return;
    try {
      await widget.sendGeoShare(
        threadId: target.thread.threadId,
        senderId: widget.myUid,
        recipientUid: target.otherUser.uid,
        share: GeoShare.pin(point: place.point, label: place.label),
      );
      _snack('Sent to ${widget.nameOf(target.otherUser)}.');
    } catch (error) {
      _snack('Could not send: $error');
    }
  }

  Future<void> _notifyOnArrival(SavedPlace place) async {
    final target = await _pickContact('Tell on arrival at "${place.label}"');
    if (target == null || !mounted) return;
    if (!await ensureArrivalPermissions(context) || !mounted) return;
    await widget.arrivalService.add(
      ownerUid: widget.myUid,
      threadId: target.thread.threadId,
      recipientUid: target.otherUser.uid,
      label: place.label,
      point: place.point,
      radiusMeters: place.radiusMeters,
      placeId: place.id,
    );
    final error = widget.arrivalService.fenceError;
    _snack(
      error == null
          ? '${widget.nameOf(target.otherUser)} will be told when you reach '
                '${place.label}.'
          : 'Saved, but not active: $error',
    );
  }

  Future<void> _editPlace(SavedPlace place) async {
    await editSavedPlace(
      context,
      places: widget.placesService,
      place: place,
      others: [
        for (final p in _places)
          if (p.id != place.id) p,
      ],
    );
  }

  String _recipientName(ArrivalAlert alert) {
    for (final item in widget.contacts()) {
      if (item.thread.threadId == alert.threadId) {
        return widget.nameOf(item.otherUser);
      }
    }
    return 'your contact';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My locations')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPlace,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add place'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Saved places', style: textTheme.titleSmall),
          ),
          if (_places.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Add a place, then send it to a contact whenever you like, or '
                'have them told automatically when you arrive.',
              ),
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
                '${place.visitCount > 0 ? ' - visited ${place.visitCount}x' : ''}'
                '${place.temporary ? ' - temporary' : ''}',
              ),
              onTap: () => _sendNow(place),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'send':
                      unawaited(_sendNow(place));
                    case 'arrive':
                      unawaited(_notifyOnArrival(place));
                    case 'edit':
                      unawaited(_editPlace(place));
                    case 'delete':
                      unawaited(widget.placesService.remove(place.id));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'send', child: Text('Send now')),
                  PopupMenuItem(
                    value: 'arrive',
                    child: Text('Tell on arrival'),
                  ),
                  PopupMenuItem(value: 'edit', child: Text('Radius and tag')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          if (_alerts.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Arrival alerts', style: textTheme.titleSmall),
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
                      ? (widget.arrivalService.fenceError != null
                            ? 'Not active: ${widget.arrivalService.fenceError}'
                            : 'Will tell ${_recipientName(alert)} within '
                                  '${alert.radiusMeters.round()} m')
                      : 'Reached - ${_recipientName(alert)} was told',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!alert.isArmed)
                      IconButton(
                        tooltip: 'Arm again',
                        icon: const Icon(Icons.replay_rounded),
                        onPressed: () => widget.arrivalService.rearm(alert.id),
                      ),
                    IconButton(
                      tooltip: 'Cancel alert',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => widget.arrivalService.remove(alert.id),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
