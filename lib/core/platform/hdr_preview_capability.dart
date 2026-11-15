import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HdrPreviewCapability {
  HdrPreviewCapability._();

  static final instance = HdrPreviewCapability._();
  static const _channel = MethodChannel('photo_vault/hdr_preview');

  final available = ValueNotifier<bool>(false);
  Future<bool>? _load;

  Future<bool> load() => _load ??= _loadAvailability();

  Future<bool> _loadAvailability() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      available.value = false;
      return false;
    }

    try {
      final supported = await _channel.invokeMethod<bool>('isSupported');
      available.value = supported ?? false;
    } on PlatformException catch (error) {
      debugPrint('Could not determine HDR preview support: ${error.message}');
      available.value = false;
    } on MissingPluginException {
      available.value = false;
    }
    return available.value;
  }

  @visibleForTesting
  void resetForTesting() {
    _load = null;
    available.value = false;
  }
}
