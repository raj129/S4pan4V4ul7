import 'package:flutter/material.dart';

import '../mock/mock_location_controller.dart';

/// Wraps the whole app and pins a reminder strip to the top while a mock
/// location is active, with a one-tap switch back to the real GPS.
class MockLocationBanner extends StatelessWidget {
  const MockLocationBanner({
    super.key,
    required this.controller,
    required this.child,
    this.visibilityListenable,
    this.isVisible,
    this.onOpen,
  });

  final MockLocationController controller;
  final Widget child;

  /// Extra gate, e.g. hide while the disguise screen is showing.
  final Listenable? visibilityListenable;
  final bool Function()? isVisible;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, ?visibilityListenable]),
      builder: (context, _) {
        final show = controller.isActive && (isVisible?.call() ?? true);
        if (!show) return child;
        return Column(
          children: [
            _Strip(controller: controller, onOpen: onOpen),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.controller, this.onOpen});

  final MockLocationController controller;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final systemWide = controller.systemWideRunning;
    return Material(
      key: const Key('mock-location-banner'),
      color: scheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Icon(
                Icons.location_searching,
                size: 18,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mock location${systemWide ? ' (system-wide)' : ''} · '
                  '${controller.statusLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onOpen != null)
                TextButton(
                  onPressed: onOpen,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onTertiaryContainer,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Open'),
                ),
              TextButton(
                key: const Key('mock-location-banner-use-real'),
                onPressed: controller.useRealGps,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onTertiaryContainer,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Use real GPS'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
