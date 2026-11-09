import 'package:equatable/equatable.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// A device contact with the phone numbers saved for it.
class PhoneContact extends Equatable {
  const PhoneContact({required this.name, required this.numbers});

  final String name;
  final List<String> numbers;

  @override
  List<Object?> get props => [name, numbers];
}

/// The device address book filtered to contacts with phone numbers.
abstract class PhoneContactSource {
  Future<bool> requestPermission();

  Future<List<PhoneContact>> read();
}

class PlatformPhoneContactSource implements PhoneContactSource {
  const PlatformPhoneContactSource();

  @override
  Future<bool> requestPermission() async {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  @override
  Future<List<PhoneContact>> read() async {
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.phone},
    );
    final result = <PhoneContact>[
      for (final contact in contacts)
        if (contact.phones.isNotEmpty)
          PhoneContact(
            name: contact.displayName?.trim() ?? '',
            numbers: [
              for (final phone in contact.phones)
                if (phone.number.trim().isNotEmpty) phone.number.trim(),
            ],
          ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }
}
