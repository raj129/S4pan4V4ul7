import 'dart:async';

import 'package:flutter/material.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import '../../application/services/arrival_alert_service.dart';
import '../../application/services/saved_places_service.dart';
import '../../domain/entities/arrival_alert.dart';
import '../widgets/arrival_place_sheets.dart';
import '../../domain/entities/chat_user.dart';
import '../../domain/entities/geo_share.dart';
import '../../domain/entities/saved_place.dart';
import '../state/thread_list_cubit.dart';
import '../widgets/arrival_permissions.dart';
import 'geo_share_map_screen.dart';

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

  void _previewOnMap(SavedPlace place) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GeoShareMapScreen(
          share: GeoShare.pin(point: place.point, label: place.label),
        ),
      ),
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
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const SectionHeader('Saved places'),
          if (_places.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Card(
                color: cs.surfaceContainerLow,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      SettingsIconBadge(
                        icon: Icons.place_outlined,
                        size: 52,
                        backgroundColor: cs.primaryContainer,
                        iconColor: cs.onPrimaryContainer,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'No saved places yet',
                        style: textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Save places you visit often to send them quickly or '
                        'notify contacts automatically when you arrive.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                children: [
                  for (final place in _places) ...[
                    _SavedPlaceCard(
                      place: place,
                      onPreview: () => _previewOnMap(place),
                      onSend: () => _sendNow(place),
                      onArrivalAlert: () => _notifyOnArrival(place),
                      onEdit: () => _editPlace(place),
                      onDelete: () =>
                          unawaited(widget.placesService.remove(place.id)),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          if (_alerts.isNotEmpty) ...[
            const SectionHeader('Arrival alerts'),
            SettingsCard(
              children: [
                for (final alert in _alerts)
                  ListTile(
                    leading: SettingsIconBadge(
                      icon: alert.isArmed
                          ? Icons.notifications_active_rounded
                          : Icons.check_circle_rounded,
                      backgroundColor: alert.isArmed
                          ? cs.primaryContainer
                          : cs.tertiaryContainer,
                      iconColor: alert.isArmed
                          ? cs.onPrimaryContainer
                          : cs.onTertiaryContainer,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            alert.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _AlertStatusBadge(isArmed: alert.isArmed),
                      ],
                    ),
                    subtitle: Text(
                      alert.isArmed
                          ? (widget.arrivalService.fenceError != null
                                ? 'Not active: ${widget.arrivalService.fenceError}'
                                : 'Will tell ${_recipientName(alert)} within '
                                      '${alert.radiusMeters.round()} m')
                          : 'Reached · ${_recipientName(alert)} was told',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!alert.isArmed)
                          IconButton(
                            tooltip: 'Arm again',
                            icon: const Icon(Icons.replay_rounded),
                            onPressed: () =>
                                widget.arrivalService.rearm(alert.id),
                          ),
                        IconButton(
                          tooltip: 'Cancel alert',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () =>
                              widget.arrivalService.remove(alert.id),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SavedPlaceCard extends StatelessWidget {
  const _SavedPlaceCard({
    required this.place,
    required this.onPreview,
    required this.onSend,
    required this.onArrivalAlert,
    required this.onEdit,
    required this.onDelete,
  });

  final SavedPlace place;
  final VoidCallback onPreview;
  final VoidCallback onSend;
  final VoidCallback onArrivalAlert;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tagColor = Color(place.tagColor ?? cs.primary.toARGB32());

    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPreview,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tagColor.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.place_rounded, color: tagColor, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${place.tagName ?? 'Saved place'} · '
                          '${place.radiusMeters.round()} m'
                          '${place.visitCount > 0 ? ' · visited ${place.visitCount}x' : ''}'
                          '${place.temporary ? ' · temporary' : ''}'
                          ' · Tap to view map',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEdit();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Radius and tag'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: onSend,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: onArrivalAlert,
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      size: 16,
                    ),
                    label: const Text('Arrival alert'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertStatusBadge extends StatelessWidget {
  const _AlertStatusBadge({required this.isArmed});

  final bool isArmed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isArmed ? cs.primaryContainer : cs.tertiaryContainer;
    final fg = isArmed ? cs.onPrimaryContainer : cs.onTertiaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          isArmed ? 'Armed' : 'Reached',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
