import 'package:flutter/material.dart';

import '../../di/chat_dependencies.dart';
import '../state/thread_list_cubit.dart';
import 'my_locations_screen.dart';

/// Hosts [MyLocationsScreen] outside the chat list, e.g. from the drawer.
/// Watches the thread list itself so "Send now" has contacts to offer.
class MyLocationsRoute extends StatefulWidget {
  const MyLocationsRoute({super.key, required this.dependencies});

  final ChatDependencies dependencies;

  @override
  State<MyLocationsRoute> createState() => _MyLocationsRouteState();
}

class _MyLocationsRouteState extends State<MyLocationsRoute> {
  late final ThreadListCubit _threads;

  @override
  void initState() {
    super.initState();
    final deps = widget.dependencies;
    _threads = ThreadListCubit(
      threadRepository: deps.threadRepository,
      userRepository: deps.userRepository,
      messageRepository: deps.messageRepository,
      mediaRepository: deps.mediaRepository,
      presenceRepository: deps.presenceRepository,
      messageCache: deps.messageCache,
      myUid: deps.authService.currentUid ?? '',
    )..startWatching();
  }

  @override
  void dispose() {
    _threads.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = widget.dependencies;
    final places = deps.savedPlacesService;
    final arrivals = deps.arrivalAlertService;
    final uid = deps.authService.currentUid;
    if (places == null || arrivals == null || uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My locations')),
        body: const Center(child: Text('Sign in to chat to use My locations.')),
      );
    }
    return MyLocationsScreen(
      myUid: uid,
      placesService: places,
      arrivalService: arrivals,
      sendGeoShare: deps.sendGeoShare,
      contacts: () => switch (_threads.state) {
        ThreadListLoaded(:final items) => items,
        _ => const [],
      },
      nameOf: (user) => deps.profileService.nameFor(user),
    );
  }
}
