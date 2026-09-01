import 'package:equatable/equatable.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../domain/entities/chat_user.dart';
import '../../domain/repositories/user_repository.dart';

/// A device contact that turned out to be a registered chat user.
class MatchedContact extends Equatable {
  const MatchedContact({required this.user, required this.contactName});

  final ChatUser user;

  /// The name as saved in the address book, which is more recognisable to the
  /// user than the display name attached to the Google account.
  final String contactName;

  @override
  List<Object?> get props => [user, contactName];
}

/// Result of a contact scan, including why it produced nothing.
class ContactDiscoveryResult extends Equatable {
  const ContactDiscoveryResult({
    required this.matches,
    required this.permissionGranted,
    this.scannedEmails = 0,
  });

  const ContactDiscoveryResult.denied()
    : matches = const [],
      permissionGranted = false,
      scannedEmails = 0;

  final List<MatchedContact> matches;

  /// False when the user declined the contacts permission, so the UI can offer
  /// the manual email path instead of showing a bare empty list.
  final bool permissionGranted;

  final int scannedEmails;

  @override
  List<Object?> get props => [matches, permissionGranted, scannedEmails];
}

/// One address-book entry, reduced to what matching needs.
///
/// A plain DTO rather than the plugin's `Contact`, so the matching logic can be
/// exercised without a platform channel.
class DeviceContact {
  const DeviceContact({required this.name, required this.emails});

  final String name;
  final List<String> emails;
}

/// The device address book, behind a seam for testing.
abstract class ContactSource {
  /// Ask for read access. False means the user declined.
  Future<bool> requestPermission();

  /// Every contact that has at least one email address.
  Future<List<DeviceContact>> read();
}

/// Real address book, backed by flutter_contacts.
class PlatformContactSource implements ContactSource {
  const PlatformContactSource();

  @override
  Future<bool> requestPermission() async {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    // `limited` (iOS 18+) still yields a usable subset, so it counts as granted.
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  @override
  Future<List<DeviceContact>> read() async {
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.email},
    );
    return [
      for (final contact in contacts)
        DeviceContact(
          name: contact.displayName?.trim() ?? '',
          emails: [for (final e in contact.emails) e.address],
        ),
    ];
  }
}

/// Finds which of the device's contacts are already registered chat users.
///
/// Only email addresses are used, because the chat identity *is* the Google
/// account: matching by phone number would need a directory the app does not
/// have.
class ContactDiscoveryService {
  ContactDiscoveryService({
    required UserRepository userRepository,
    ContactSource contacts = const PlatformContactSource(),
  }) : _userRepository = userRepository,
       _contacts = contacts;

  final UserRepository _userRepository;
  final ContactSource _contacts;

  /// Firestore `whereIn` accepts at most 30 values per query.
  static const _lookupChunkSize = 30;

  Future<ContactDiscoveryResult> discover({required String myUid}) async {
    if (!await _contacts.requestPermission()) {
      return const ContactDiscoveryResult.denied();
    }

    final contacts = await _contacts.read();

    // Normalise to lower case and keep the first address-book name seen for
    // each address, so duplicate contact entries collapse to one row.
    final nameByEmail = <String, String>{};
    for (final contact in contacts) {
      for (final email in contact.emails) {
        final address = email.trim().toLowerCase();
        if (address.isEmpty || !address.contains('@')) continue;
        nameByEmail.putIfAbsent(address, () {
          final name = contact.name.trim();
          return name.isEmpty ? address : name;
        });
      }
    }

    if (nameByEmail.isEmpty) {
      return const ContactDiscoveryResult(
        matches: [],
        permissionGranted: true,
      );
    }

    final emails = nameByEmail.keys.toList();
    final found = <MatchedContact>[];
    for (var i = 0; i < emails.length; i += _lookupChunkSize) {
      final chunk = emails.sublist(
        i,
        (i + _lookupChunkSize).clamp(0, emails.length),
      );
      final users = await _userRepository.getUsersByEmails(chunk);
      for (final user in users) {
        // Never offer a chat with yourself.
        if (user.uid == myUid) continue;
        found.add(
          MatchedContact(
            user: user,
            contactName: nameByEmail[user.email.toLowerCase()] ?? user.email,
          ),
        );
      }
    }

    found.sort(
      (a, b) =>
          a.contactName.toLowerCase().compareTo(b.contactName.toLowerCase()),
    );

    return ContactDiscoveryResult(
      matches: found,
      permissionGranted: true,
      scannedEmails: emails.length,
    );
  }
}
