import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../vault/data/repositories/storage_string_kv.dart';
import '../../domain/entities/geo_share.dart';
import '../../domain/entities/saved_place.dart';

/// The user's own list of places, kept in secure storage on this device.
class SavedPlacesService {
  SavedPlacesService({required StorageStringKv store}) : _store = store;

  static const storageKey = 'chat.saved_places.v1';

  final StorageStringKv _store;
  final _uuid = const Uuid();
  final _changes = StreamController<List<SavedPlace>>.broadcast();

  List<SavedPlace> _places = const [];
  bool _loaded = false;

  Stream<List<SavedPlace>> get changes => _changes.stream;

  Future<List<SavedPlace>> placesFor(String ownerUid) async {
    await _load();
    return [
      for (final p in _places)
        if (p.ownerUid == ownerUid) p,
    ];
  }

  Future<SavedPlace> add({
    required String ownerUid,
    required String label,
    required GeoPoint point,
  }) async {
    await _load();
    final place = SavedPlace(
      id: _uuid.v4(),
      ownerUid: ownerUid,
      label: label.trim(),
      point: point,
    );
    _places = [..._places, place];
    await _persist();
    return place;
  }

  Future<void> remove(String id) async {
    await _load();
    _places = [
      for (final p in _places)
        if (p.id != id) p,
    ];
    await _persist();
  }

  Future<void> clear() async {
    _places = const [];
    _loaded = false;
    await _store.delete(storageKey);
    if (!_changes.isClosed) _changes.add(_places);
  }

  Future<void> _load() async {
    if (_loaded) return;
    _places = SavedPlace.decodeList(await _store.read(storageKey));
    _loaded = true;
  }

  Future<void> _persist() async {
    await _store.write(storageKey, SavedPlace.encodeList(_places));
    if (!_changes.isClosed) _changes.add(_places);
  }

  void dispose() => _changes.close();
}
