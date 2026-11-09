import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/calls/data/phone_contact_source.dart';
import 'package:photo_vault/features/calls/domain/call_log_entry.dart';
import 'package:photo_vault/features/calls/domain/call_log_repository.dart';
import 'package:photo_vault/features/calls/presentation/call_log_screen.dart';

class _FakeCallLogRepository implements CallLogRepository {
  _FakeCallLogRepository(this.entries, {this.listError});

  final List<CallLogEntry> entries;
  final String? listError;
  final added = <String>[];
  final updates = <String, ({DateTime timestamp, int durationSeconds})>{};

  @override
  bool get isSupported => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<List<CallLogEntry>> list({int limit = 500}) async {
    if (listError != null) throw CallLogException(listError!);
    return entries;
  }

  @override
  Future<bool> add({
    required String number,
    required CallLogType type,
    required DateTime timestamp,
    String? name,
    int durationSeconds = 0,
  }) async {
    added.add(number);
    return true;
  }

  @override
  Future<bool> update({
    required String id,
    required DateTime timestamp,
    required int durationSeconds,
  }) async {
    updates[id] = (timestamp: timestamp, durationSeconds: durationSeconds);
    return true;
  }
}

class _FakeContactSource implements PhoneContactSource {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<List<PhoneContact>> read() async => const [];
}

void main() {
  test('maps Android call type constants', () {
    expect(CallLogType.fromPlatform(1), CallLogType.incoming);
    expect(CallLogType.fromPlatform(2), CallLogType.outgoing);
    expect(CallLogType.fromPlatform(3), CallLogType.missed);
    expect(CallLogType.fromPlatform(99), isNull);
  });

  testWidgets('lists call log entries with names and missed styling', (
    tester,
  ) async {
    final repository = _FakeCallLogRepository([
      CallLogEntry(
        id: '1',
        number: '+911234567890',
        name: 'Asha',
        type: CallLogType.missed,
        timestamp: DateTime(2026, 11, 9, 10, 30),
      ),
      CallLogEntry(
        id: '2',
        number: '5551234',
        type: CallLogType.outgoing,
        timestamp: DateTime(2026, 11, 8, 18, 5),
        durationSeconds: 75,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: CallLogScreen(
          repository: repository,
          contactSource: _FakeContactSource(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('5551234'), findsOneWidget);
    expect(find.byIcon(Icons.call_missed), findsOneWidget);
    expect(find.byIcon(Icons.call_made), findsOneWidget);
    expect(find.text('Add call'), findsOneWidget);
  });

  testWidgets(
    'shows the error and a Retry button when the log cannot be read',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CallLogScreen(
            repository: _FakeCallLogRepository(
              const [],
              listError: 'permission_denied',
            ),
            contactSource: _FakeContactSource(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Could not read the call log.\npermission_denied'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No calls in the call log yet.'), findsNothing);
    },
  );

  testWidgets('tapping an incoming entry edits its duration and time', (
    tester,
  ) async {
    final repository = _FakeCallLogRepository([
      CallLogEntry(
        id: '7',
        number: '5551234',
        type: CallLogType.incoming,
        timestamp: DateTime(2026, 11, 8, 18, 5),
        durationSeconds: 75,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: CallLogScreen(
          repository: repository,
          contactSource: _FakeContactSource(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('5551234'));
    await tester.pumpAndSettle();

    expect(find.text('Edit call'), findsOneWidget);
    expect(find.text('Minutes'), findsOneWidget);
    expect(find.text('Seconds'), findsOneWidget);
    String fieldText(String label) => tester
        .widget<TextField>(find.widgetWithText(TextField, label))
        .controller!
        .text;
    expect(fieldText('Minutes'), '1');
    expect(fieldText('Seconds'), '15');
  });

  testWidgets('missed calls have no duration field when editing', (
    tester,
  ) async {
    final repository = _FakeCallLogRepository([
      CallLogEntry(
        id: '8',
        number: '5550000',
        type: CallLogType.missed,
        timestamp: DateTime(2026, 11, 8, 18, 5),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: CallLogScreen(
          repository: repository,
          contactSource: _FakeContactSource(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('5550000'));
    await tester.pumpAndSettle();

    expect(find.text('Minutes'), findsNothing);
    expect(find.text('Duration'), findsNothing);
  });

  testWidgets('saving an edit passes the new duration to the repository', (
    tester,
  ) async {
    final repository = _FakeCallLogRepository([
      CallLogEntry(
        id: '9',
        number: '5559999',
        type: CallLogType.outgoing,
        timestamp: DateTime(2026, 11, 8, 18, 5),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: CallLogScreen(
          repository: repository,
          contactSource: _FakeContactSource(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('5559999'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '3');
    await tester.enterText(find.widgetWithText(TextField, 'Seconds'), '20');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(repository.updates['9']?.durationSeconds, 200);
    expect(repository.updates['9']?.timestamp, DateTime(2026, 11, 8, 18, 5));
  });

  testWidgets('shows empty state when there are no entries', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CallLogScreen(
          repository: _FakeCallLogRepository(const []),
          contactSource: _FakeContactSource(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No calls in the call log yet.'), findsOneWidget);
  });
}
