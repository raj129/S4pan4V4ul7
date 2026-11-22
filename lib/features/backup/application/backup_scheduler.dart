import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:photo_vault/features/chat/application/services/chat_backup_scheduler.dart'
    show chatBackupCallbackDispatcher;
import 'package:workmanager/workmanager.dart';

/// Periodic nightly backup task identifier (kept identical for upgrade continuity).
const nightlyBackupTaskName = 'photo_vault.chat_backup.nightly';

/// One-off network-constrained catch-up task identifier.
const catchUpBackupTaskName = 'photo_vault.backup.catchup';

/// Target local hour (2 AM) for automatic nightly backups.
const backupTargetHour = 2;

/// Time from [now] until the next [backupTargetHour]:00 local time.
@visibleForTesting
Duration delayUntilNextBackup(DateTime now) {
  var next = DateTime(now.year, now.month, now.day, backupTargetHour);
  if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
  return next.difference(now);
}

/// Schedules the silent nightly backup (Android only; desktop backs up on open).
Future<void> scheduleNightlyBackup() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(chatBackupCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    nightlyBackupTaskName,
    nightlyBackupTaskName,
    frequency: const Duration(hours: 24),
    initialDelay: delayUntilNextBackup(DateTime.now()),
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: true,
    ),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// Schedules a silent one-off OS catch-up run as soon as the required network
/// becomes available (unmetered when [wifiOnly] is true, connected otherwise).
Future<void> schedulePendingBackupCatchUp({required bool wifiOnly}) async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(chatBackupCallbackDispatcher);
  await Workmanager().registerOneOffTask(
    catchUpBackupTaskName,
    catchUpBackupTaskName,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(
      networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 5),
  );
}
