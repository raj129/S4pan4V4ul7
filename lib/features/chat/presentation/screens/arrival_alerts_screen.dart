import 'dart:async';

import 'package:flutter/material.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import '../../application/services/arrival_alert_service.dart';
import '../../application/services/saved_places_service.dart';
import '../../domain/entities/arrival_alert.dart';
import '../../domain/entities/geo_share.dart';
import '../../domain/entities/saved_place.dart';
import '../widgets/arrival_permissions.dart';
import '../widgets/arrival_place_sheets.dart';
import 'geo_share_map_screen.dart';

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

  void _previewOnMap(SavedPlace place) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GeoShareMapScreen(
          share: GeoShare.pin(point: place.point, label: place.label),
        ),
      ),
    );
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
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const SectionHeader('My places'),
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
                        size: 48,
                        backgroundColor: cs.primaryContainer,
                        iconColor: cs.onPrimaryContainer,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text('No saved places yet', style: textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Add a place with "New place" to notify '
                        '${widget.recipientName} when you arrive.',
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
                    _ArrivalPlaceCard(
                      place: place,
                      isArmed: _isArmedFor(place),
                      onPreview: () => _previewOnMap(place),
                      onTellOnArrival: () => _tellOnArrival(place),
                      onSendNow: widget.onSendShare == null
                          ? null
                          : () => _sendNow(place),
                      onEdit: () => editSavedPlace(
                        context,
                        places: widget.places,
                        place: place,
                        others: [
                          for (final p in _places)
                            if (p.id != place.id) p,
                        ],
                      ),
                      onDelete: () => widget.places.remove(place.id),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          const SectionHeader('Armed alerts'),
          if (_alerts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: InfoBanner(
                message:
                    'When you reach an armed place, ${widget.recipientName} is '
                    'told automatically.',
                tone: InfoBannerTone.info,
              ),
            )
          else
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
                          ? (widget.service.fenceError != null
                                ? 'Not active: ${widget.service.fenceError}'
                                : 'Will notify ${widget.recipientName} within '
                                      '${alert.radiusMeters.round()} m')
                          : 'Reached · ${widget.recipientName} was notified',
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
        ],
      ),
    );
  }
}

class _ArrivalPlaceCard extends StatelessWidget {
  const _ArrivalPlaceCard({
    required this.place,
    required this.isArmed,
    required this.onPreview,
    required this.onTellOnArrival,
    required this.onEdit,
    required this.onDelete,
    this.onSendNow,
  });

  final SavedPlace place;
  final bool isArmed;
  final VoidCallback onPreview;
  final VoidCallback onTellOnArrival;
  final VoidCallback? onSendNow;
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                place.label,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isArmed) ...[
                              const SizedBox(width: 6),
                              const _AlertStatusBadge(isArmed: true),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${place.tagName ?? 'Saved place'} · '
                          '${place.radiusMeters.round()} m · Tap to view map',
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
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
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
                    onPressed: onTellOnArrival,
                    icon: Icon(
                      isArmed
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_active_outlined,
                      size: 16,
                    ),
                    label: Text(isArmed ? 'Armed' : 'Tell on arrival'),
                  ),
                  if (onSendNow != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: onSendNow,
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Send now'),
                    ),
                  ],
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
