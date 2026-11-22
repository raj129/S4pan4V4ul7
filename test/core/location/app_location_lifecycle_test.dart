import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/location/app_location.dart';
import 'package:photo_vault/core/location/geo_fix.dart';
import 'package:photo_vault/core/location/location_source.dart';

class _Source extends LocationSource {
  // ignore: close_sinks - closed by each test.
  final stream = StreamController<GeoFix>();
  bool failSetup = false;
  @override
  Stream<GeoFix> updates([
    LocationUpdateConfig config = const LocationUpdateConfig(),
  ]) {
    if (failSetup) throw StateError('setup failed');
    return stream.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('terminal real-source completion closes the public stream', () async {
    final source = _Source();
    final location = AppLocation(real: source);
    addTearDown(location.mock.dispose);
    var done = false;
    location.updates().listen((_) {}, onDone: () => done = true);
    await pumpEventQueue();
    await source.stream.close();
    await pumpEventQueue();
    expect(done, isTrue);
  });

  test('source setup errors reach the public subscriber', () async {
    final source = _Source()..failSetup = true;
    final location = AppLocation(real: source);
    addTearDown(location.mock.dispose);
    final errors = <Object>[];
    final sub = location.updates().listen((_) {}, onError: errors.add);
    await pumpEventQueue();
    expect(errors.single, isA<StateError>());
    await sub.cancel();
    unawaited(source.stream.close());
  });

  test('old source completion cannot close the selected mock source', () async {
    final source = _Source();
    final location = AppLocation(real: source);
    addTearDown(location.mock.dispose);
    final fixes = <GeoFix>[];
    var done = false;
    final sub = location.updates().listen(fixes.add, onDone: () => done = true);
    await pumpEventQueue();
    location.mock.enableFixed(const GeoCoord(1, 2));
    unawaited(source.stream.close());
    await pumpEventQueue();
    expect(done, isFalse);
    expect(fixes.last.isMock, isTrue);
    await sub.cancel();
  });

  test('pause and resume are preserved through a source switch', () async {
    final source = _Source();
    final location = AppLocation(real: source);
    addTearDown(location.mock.dispose);
    final fixes = <GeoFix>[];
    final sub = location.updates().listen(fixes.add);
    await pumpEventQueue();
    sub.pause();
    location.mock.enableFixed(const GeoCoord(1, 2));
    await pumpEventQueue();
    expect(fixes, isEmpty);
    sub.resume();
    await pumpEventQueue();
    expect(fixes.last.isMock, isTrue);
    await sub.cancel();
    await source.stream.close();
  });

  test(
    'obsolete switch failures cannot interrupt the selected source',
    () async {
      final cancellation = Completer<void>();
      final source = _Source();
      source.stream.onCancel = () => cancellation.future;
      final location = AppLocation(real: source);
      addTearDown(location.mock.dispose);
      final errors = <Object>[];
      final fixes = <GeoFix>[];
      final sub = location.updates().listen(fixes.add, onError: errors.add);
      await pumpEventQueue();
      location.mock.enableFixed(const GeoCoord(1, 2));
      await pumpEventQueue();
      await location.mock.useRealGps();
      location.mock.enableFixed(const GeoCoord(3, 4));
      cancellation.completeError(StateError('obsolete cancellation failed'));
      await pumpEventQueue();
      expect(errors, isEmpty);
      expect(fixes.last.latitude, 3);
      expect(fixes.last.isMock, isTrue);
      await sub.cancel();
      unawaited(source.stream.close());
    },
  );

  test(
    'PlatformException on stream cancel is ignored',
    () async {
      final source = _Source();
      source.stream.onCancel = () => Future<void>.error(
        Exception('No active stream to cancel'),
      );
      final location = AppLocation(real: source);
      addTearDown(location.mock.dispose);
      final sub = location.updates().listen((_) {});
      await pumpEventQueue();
      await expectLater(sub.cancel(), completes);
    },
  );
}
