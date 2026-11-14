import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/calls/data/phone_contact_source.dart';
import 'package:photo_vault/features/chat/presentation/widgets/data_sms_number_dialog.dart';

class _Contacts implements PhoneContactSource {
  bool granted = true;
  bool fail = false;
  int requests = 0;
  int reads = 0;
  Completer<bool>? permission;
  List<PhoneContact> contacts = const [
    PhoneContact(name: 'Alice', numbers: ['9876543210', '+441234567890']),
    PhoneContact(name: 'Bob', numbers: ['+12025550123']),
  ];

  @override
  Future<bool> requestPermission() async {
    requests++;
    if (permission != null) return permission!.future;
    return granted;
  }

  @override
  Future<List<PhoneContact>> read() async {
    reads++;
    if (fail) throw StateError('address book unavailable');
    return contacts;
  }
}

void main() {
  late _Contacts contacts;
  String? saved;
  bool? result;
  int writes = 0;

  setUp(() {
    contacts = _Contacts();
    saved = null;
    result = null;
    writes = 0;
  });

  Future<void> open(
    WidgetTester tester, {
    String? current,
    Future<void> Function(String?)? save,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDataSmsNumberDialog(
                  context,
                  currentNumber: current,
                  contacts: contacts,
                  saveNumber:
                      save ??
                      (number) async {
                        writes++;
                        saved = number;
                      },
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.text('Choose from contacts'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'manual save normalizes, validates, and does not request contacts',
    (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Use an international phone number'),
        findsOneWidget,
      );
      expect(writes, 0);
      await tester.enterText(find.byType(TextField), '+91 (98765) 43210');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, '+919876543210');
      expect(result, isTrue);
      expect(contacts.requests, 0);
    },
  );

  testWidgets('existing number can be changed, cancelled or removed', (
    tester,
  ) async {
    await open(tester, current: '+12025550123');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '+12025550123',
    );
    await tester.enterText(find.byType(TextField), '+441234567890');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(result, isNull);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(saved, isNull);
    expect(result, isFalse);
  });

  testWidgets('contact search offers every number and requires confirmation', (
    tester,
  ) async {
    await open(tester);
    await pick(tester);
    expect(contacts.requests, 1);
    expect(find.text('Alice'), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).last, 'bob');
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    await tester.enterText(find.byType(TextField).last, '441234');
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.text('+441234567890'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '+441234567890',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, '+441234567890');
  });

  testWidgets('local contact number requires an explicit country code', (
    tester,
  ) async {
    await open(tester);
    await pick(tester);
    await tester.tap(find.text('9876543210'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Use an international phone number'),
      findsOneWidget,
    );
    expect(writes, 0);
  });

  testWidgets(
    'denied contacts retain manual entry and never read address book',
    (tester) async {
      contacts.granted = false;
      await open(tester);
      await pick(tester);
      expect(find.textContaining('Contacts access denied'), findsOneWidget);
      expect(contacts.reads, 0);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '+12025550123');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, '+12025550123');
    },
  );

  testWidgets('empty and failed contacts are visible and retryable', (
    tester,
  ) async {
    contacts.fail = true;
    await open(tester);
    await pick(tester);
    expect(find.textContaining('Could not read contacts'), findsOneWidget);
    contacts.fail = false;
    contacts.contacts = [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No matching phone numbers.'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('Data SMS recipient'), findsOneWidget);
  });

  testWidgets('save errors keep editor open and prevent concurrent writes', (
    tester,
  ) async {
    final pending = Completer<void>();
    await open(
      tester,
      current: '+12025550123',
      save: (_) {
        writes++;
        return pending.future;
      },
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(writes, 1);
    pending.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save number'), findsOneWidget);
    expect(find.text('Data SMS recipient'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late contacts permission after disposal is ignored', (
    tester,
  ) async {
    final permission = Completer<bool>();
    contacts.permission = permission;
    await open(tester);
    await tester.tap(find.text('Choose from contacts'));
    await tester.pump();
    expect(contacts.requests, 1);
    await tester.pumpWidget(const SizedBox());
    permission.complete(true);
    await tester.pump();
    expect(contacts.reads, 0);
    expect(tester.takeException(), isNull);
  });
}
