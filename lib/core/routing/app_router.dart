import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/user_mode.dart';
import '../../domain/entities/vault_photo.dart';
import '../../domain/entities/vault_status.dart';
import '../../presentation/app/chat_app.dart';
import '../../presentation/app/main_scaffold.dart';
import '../../presentation/screens/files/files_screen.dart';
import '../../presentation/screens/gallery/gallery_home_screen.dart';
import '../../presentation/screens/gallery/gallery_photo_viewer_screen.dart';
import '../../presentation/screens/import/import_screen.dart';
import '../../presentation/screens/lock/lock_screen.dart';
import '../../presentation/screens/onboarding/google_signin_screen.dart';
import '../../presentation/screens/onboarding/pin_screens.dart';
import '../../presentation/screens/onboarding/vault_creation_screen.dart';
import '../../presentation/screens/onboarding/welcome_screen.dart';
import '../../presentation/screens/restore/restore_flow_screen.dart';
import '../../presentation/screens/settings/change_pin_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/trash/trash_screen.dart';
import '../../presentation/state/onboarding/onboarding_cubit.dart';
import '../../presentation/state/onboarding/onboarding_state.dart';
import '../app/app_session.dart';
import '../di/app_dependencies.dart';

/// Builds the app's [GoRouter] configuration.
///
/// Extracted from `_VaultAppState._buildRouter` so the redirect/guard logic
/// and route table can be read (and unit tested against a fake
/// [AppDependencies]/[AppSessionState]) without needing the rest of the app
/// widget. Behavior is unchanged from the original inline implementation.
GoRouter buildAppRouter({
  required AppDependencies deps,
  required AppSessionState session,
  required OnboardingCubit onboardingCubit,
  required Future<void> Function() onSettingsChanged,
}) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: session,
    redirect: (context, state) => _redirect(deps, session, state),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => BlocProvider.value(
          value: onboardingCubit,
          child: BlocConsumer<OnboardingCubit, OnboardingState>(
            listener: (context, onboardingState) => _onOnboardingStateChanged(
              context,
              onboardingState,
              deps: deps,
              session: session,
            ),
            builder: _buildOnboardingStep,
          ),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => MainScaffold(
          navigationShell: navigationShell,
          importManager: deps.importManager,
        ),
        branches: [
          StatefulShellBranch(routes: [_galleryRoute(deps, session)]),
          StatefulShellBranch(routes: [_chatRoute(deps, session)]),
          StatefulShellBranch(routes: [_trashRoute(deps)]),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/files', builder: (_, _) => const FilesScreen()),
            ],
          ),
        ],
      ),
      _settingsRoute(deps, session, onSettingsChanged),
      _lockRoute(deps, session),
      _restoreRoute(deps, session),
      _importRoute(deps, session, path: '/import', autoOpenShareReview: false),
      _importRoute(
        deps,
        session,
        path: '/import/share-intent',
        autoOpenShareReview: true,
      ),
    ],
  );
}

Future<String?> _redirect(
  AppDependencies deps,
  AppSessionState session,
  GoRouterState state,
) async {
  final status = await deps.vaultRepository.getStatus();
  final loc = state.matchedLocation;
  final isReady = status == VaultStatus.ready;
  final isLockRoute = loc == '/lock';
  final isOnboarding = loc.startsWith('/onboarding');
  final isRestoreRoute = loc.startsWith('/restore');

  if (!isReady) {
    if (isRestoreRoute || isOnboarding) return null;
    return '/onboarding';
  }

  if (!session.isUnlocked) {
    if (isLockRoute) return null;
    final encoded = Uri.encodeComponent(loc == '/' ? '/gallery' : loc);
    return '/lock?returnTo=$encoded';
  }

  if (loc == '/' || isLockRoute || isOnboarding) {
    return '/gallery';
  }

  return null;
}

void _onOnboardingStateChanged(
  BuildContext context,
  OnboardingState state, {
  required AppDependencies deps,
  required AppSessionState session,
}) {
  if (state is! OnboardingVaultCreated) return;
  session.mode = state.mode;
  unawaited(deps.settingsRepository.saveUserMode(state.mode));
  session.unlock();
  final target =
      deps.importManager.hasPendingShareFiles ||
          deps.importManager.hasPendingImportSelection
      ? '/import/share-intent'
      : '/gallery';
  context.go(target, extra: state.mode);
}

Widget _buildOnboardingStep(BuildContext context, OnboardingState state) {
  return switch (state) {
    OnboardingInitial() => const WelcomeScreen(),
    OnboardingModeSelectedLocal() => const WelcomeScreen(),
    OnboardingGoogleSignInInProgress() => const GoogleSignInScreen(),
    OnboardingGoogleSignInSuccess() => const GoogleSignInScreen(),
    OnboardingGoogleSignInFailed() => const GoogleSignInScreen(),
    OnboardingPinEntry(mode: final m) => CreatePinScreen(mode: m),
    OnboardingPinConfirm(mode: final m) => ConfirmPinScreen(mode: m),
    OnboardingPinInvalid(mode: final m) => CreatePinScreen(mode: m),
    OnboardingCreatingVault(mode: final m) => VaultCreationScreen(mode: m),
    OnboardingVaultCreated() => const SizedBox.shrink(),
    OnboardingError() => const WelcomeScreen(),
  };
}

GoRoute _galleryRoute(AppDependencies deps, AppSessionState session) {
  return GoRoute(
    path: '/gallery',
    builder: (context, state) {
      final mode = state.extra is UserMode
          ? state.extra as UserMode
          : session.mode;
      session.mode = mode;
      return GalleryHomeScreen(
        mode: mode,
        photoRepository: deps.photoRepository,
        importManager: deps.importManager,
        photoSyncEnabled: session.photoSyncEnabled,
        vaultSession: deps.vaultSession,
        exportPhotoUseCase: deps.exportPhotoUseCase,
        unlockVaultUseCase: deps.unlockVaultUseCase,
        pinValidator: deps.pinValidator,
      );
    },
    routes: [
      GoRoute(
        path: 'photo',
        builder: (context, state) {
          final photo = state.extra as VaultPhoto?;
          if (photo == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: const Center(child: Text('No photo provided')),
            );
          }
          return GalleryPhotoViewerScreen(
            photo: photo,
            importManager: deps.importManager,
            photoRepository: deps.photoRepository,
            exportPhotoUseCase: deps.exportPhotoUseCase,
            unlockVaultUseCase: deps.unlockVaultUseCase,
            pinValidator: deps.pinValidator,
          );
        },
      ),
    ],
  );
}

GoRoute _chatRoute(AppDependencies deps, AppSessionState session) {
  return GoRoute(
    path: '/chat',
    builder: (context, state) => ChatApp(
      authRepository: deps.authRepository,
      userMode: session.mode,
    ),
  );
}

GoRoute _trashRoute(AppDependencies deps) {
  return GoRoute(
    path: '/trash',
    builder: (context, state) => TrashScreen(
      photoRepository: deps.photoRepository,
      importManager: deps.importManager,
    ),
  );
}

GoRoute _settingsRoute(
  AppDependencies deps,
  AppSessionState session,
  Future<void> Function() onSettingsChanged,
) {
  return GoRoute(
    path: '/settings',
    builder: (context, state) => SettingsScreen(
      mode: session.mode,
      settingsRepository: deps.settingsRepository,
      unlockVaultUseCase: deps.unlockVaultUseCase,
      pinValidator: deps.pinValidator,
      onSettingsChanged: onSettingsChanged,
    ),
    routes: [
      GoRoute(
        path: 'change-pin',
        builder: (context, state) => ChangePinScreen(
          changePinUseCase: deps.changePinUseCase,
          pinValidator: deps.pinValidator,
        ),
      ),
    ],
  );
}

GoRoute _lockRoute(AppDependencies deps, AppSessionState session) {
  return GoRoute(
    path: '/lock',
    builder: (context, state) {
      final returnTo = state.uri.queryParameters['returnTo'];
      final decodedReturnTo = returnTo == null
          ? '/gallery'
          : Uri.decodeComponent(returnTo);
      return LockScreen(
        unlockVaultUseCase: deps.unlockVaultUseCase,
        pinValidator: deps.pinValidator,
        onUnlocked: () {
          session.unlock();
          unawaited(deps.importManager.reconcileVaultFiles());
          final importTarget = deps.importManager.hasPendingShareFiles
              ? '/import/share-intent'
              : null;
          context.go(importTarget ?? decodedReturnTo);
        },
      );
    },
  );
}

GoRoute _restoreRoute(AppDependencies deps, AppSessionState session) {
  return GoRoute(
    path: '/restore',
    builder: (context, state) => RestoreFlowScreen(
      authRepository: deps.authRepository,
      restoreFlowService: deps.restoreFlowService,
      onRestoreCompleted: (pin, includePhotos) async {
        await deps.createVaultUseCase.execute(
          pin: pin,
          mode: UserMode.googleEnabled,
        );
        session.mode = UserMode.googleEnabled;
        await deps.settingsRepository.saveUserMode(UserMode.googleEnabled);
        await deps.settingsRepository.setPhotoSyncEnabled(includePhotos);
        session.photoSyncEnabled = includePhotos;
        session.unlock();
        if (!context.mounted) return;
        context.go('/gallery', extra: UserMode.googleEnabled);
      },
    ),
  );
}

GoRoute _importRoute(
  AppDependencies deps,
  AppSessionState session, {
  required String path,
  required bool autoOpenShareReview,
}) {
  return GoRoute(
    path: path,
    builder: (context, state) => ImportBottomSheetLauncherScreen(
      importManager: deps.importManager,
      autoOpenShareReview: autoOpenShareReview,
      onClosed: () => context.go('/gallery', extra: session.mode),
    ),
  );
}
