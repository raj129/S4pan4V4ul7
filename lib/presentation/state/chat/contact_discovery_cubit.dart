import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/services/contact_discovery_service.dart';

sealed class ContactDiscoveryState extends Equatable {
  const ContactDiscoveryState();
  @override
  List<Object?> get props => [];
}

class ContactDiscoveryIdle extends ContactDiscoveryState {
  const ContactDiscoveryIdle();
}

class ContactDiscoveryLoading extends ContactDiscoveryState {
  const ContactDiscoveryLoading();
}

class ContactDiscoveryLoaded extends ContactDiscoveryState {
  const ContactDiscoveryLoaded(this.result);
  final ContactDiscoveryResult result;
  @override
  List<Object?> get props => [result];
}

class ContactDiscoveryFailed extends ContactDiscoveryState {
  const ContactDiscoveryFailed(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

/// Drives the "people you know" list on the new-chat screen.
class ContactDiscoveryCubit extends Cubit<ContactDiscoveryState> {
  ContactDiscoveryCubit({required this.service, required this.myUid})
    : super(const ContactDiscoveryIdle());

  final ContactDiscoveryService service;
  final String myUid;

  Future<void> scan() async {
    emit(const ContactDiscoveryLoading());
    try {
      emit(ContactDiscoveryLoaded(await service.discover(myUid: myUid)));
    } catch (e) {
      emit(ContactDiscoveryFailed(e.toString()));
    }
  }
}
