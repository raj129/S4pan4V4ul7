import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/services/arrival_alert_service.dart';
import '../../domain/entities/arrival_alert.dart';
import '../../domain/entities/geo_share.dart';
import '../widgets/arrival_permissions.dart';
import 'location_picker_screen.dart';

/// Lists the places that will notify the chat partner on arrival, and lets
/// the user add several of them.
class ArrivalAlertsScreen extends StatefulWidget {
  const ArrivalAlertsScreen({
    super.key,
    required this.service,
    required this.ownerUid,
    required this.threadId,
    required this.recipientUid,
    required this.recipientName,
    this.startByAdding = false,
  });

  final ArrivalAlertService service;
  final String ownerUid;
  final String threadId;
  final String recipientUid;
  final String recipientName;

  /// Opens the place picker straight away, used by the `/arrive` command.
  final bool startByAdding;

  @override
  State<ArrivalAlertsScreen> createState() => _ArrivalAlertsScreenState();
}

class _ArrivalAlertsScreenState extends State<ArrivalAlertsScreen> {
  StreamSubscription<List<ArrivalAlert>>? _sub;
  List<ArrivalAlert> _alerts = const [];

  @override
  void initState() {
    super.initState();
    _sub = widget.service.changes.listen((_) => _refresh());
    unawaited(
      widget.service.restore().then((_) {
        _refresh();
        if (widget.startByAdding && mounted) unawaited(_add());
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(
      () => _alerts = widget.service.alertsFor(
        widget.ownerUid,
        widget.threadId,
      ),
    );
  }

  Future<bool> _ensurePermissions() => ensureArrivalPermissions(context);

  Future<void> _add() async {
    if (!await _ensurePermissions() || !mounted) return;
    final share = await Navigator.of(context).push<GeoShare>(
      MaterialPageRoute(
        builder: (_) => const LocationPickerScreen(
          allowRoute: false,
          requireLabel: true,
          title: 'Add arrival place',
          confirmLabel: 'Save place',
        ),
      ),
    );
    if (share == null || !mounted) return;
    await widget.service.add(
      ownerUid: widget.ownerUid,
      threadId: widget.threadId,
      recipientUid: widget.recipientUid,
      label: share.label,
      point: share.point,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Arrival alerts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add place'),
      ),
      body: _alerts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Add the places you are heading to. When you reach each '
                  'one, ${widget.recipientName} is told automatically.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: _alerts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final alert = _alerts[i];
                return ListTile(
                  leading: Icon(
                    alert.isArmed
                        ? Icons.notifications_active_rounded
                        : Icons.check_circle_rounded,
                    color: alert.isArmed ? cs.primary : cs.tertiary,
                  ),
                  title: Text(alert.label),
                  subtitle: Text(
                    alert.isArmed
                        ? 'Will notify ${widget.recipientName} on arrival'
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
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => widget.service.remove(alert.id),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
