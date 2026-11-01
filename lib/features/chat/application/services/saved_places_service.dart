import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../vault/data/repositories/storage_string_kv.dart';
import '../../domain/entities/geo_share.dart';
import '../../domain/entities/place_tag.dart';
import '../../domain/entities/saved_place.dart';

/// The user's own places, kept in secure storage on this device.
///
/// Every call re-reads storage, because the background arrival worker runs in
/// another isolate and may have recorded visits in between.
class SavedPlacesService {
  SavedPlacesService({
    required StorageStringKv store,
    DateTime Function()? clock,
  }) : _store = store,
       _clock = clock ?? DateTime.now;

  static const storageKey = 'chat.saved_places.v1';
  static const tagsStorageKey = 'chat.place_tags.v1';

  final StorageStringKv _store;
  final DateTime Function() _clock;
  final _uuid = const Uuid();
  final _changes = StreamController<List<SavedPlace>>.broadcast();

  Stream<List<SavedPlace>> get changes => _changes.stream;

  /// The owner's live places, most visited first, then by name.
  Future<List<SavedPlace>> placesFor(String ownerUid) async {
    final now = _clock().toUtc();
    final places = [
      for (final p in await _read())
        if (p.ownerUid == ownerUid && !p.isExpired(now)) p,
    ];
    places.sort((a, b) {
      final byVisits = b.visitCount.compareTo(a.visitCount);
      return byVisits != 0 ? byVisits : a.label.compareTo(b.label);
    });
    return places;
  }

  Future<SavedPlace> add({
    required String ownerUid,
    required String label,
    required GeoPoint point,
    double radiusMeters = SavedPlace.defaultRadiusMeters,
    PlaceTag? tag,
    bool temporary = false,
  }) async {
    final now = _clock().toUtc();
    final place = SavedPlace(
      id: _uuid.v4(),
      ownerUid: ownerUid,
      label: label.trim(),
      point: point,
      radiusMeters: radiusMeters,
      tagName: tag?.name,
      tagColor: tag?.color,
      temporary: temporary,
      expiresAt: temporary ? now.add(SavedPlace.temporaryLifetime) : null,
    );
    final places = await _read();
    await _write([...places, place]);
    return place;
  }

  /// Updates a place. A temporary place becomes a saved one when [keep] is true.
  Future<SavedPlace?> update(
    String id, {
    String? label,
    GeoPoint? point,
    double? radiusMeters,
    PlaceTag? tag,
    bool clearTag = false,
    bool keep = false,
  }) async {
    SavedPlace? updated;
    final places = await _read();
    final next = [
      for (final p in places)
        if (p.id == id)
          updated = p.copyWith(
            label: label?.trim(),
            point: point,
            radiusMeters: radiusMeters,
            tagName: tag?.name,
            tagColor: tag?.color,
            clearTag: clearTag,
            temporary: keep ? false : null,
            clearExpiry: keep,
          )
        else
          p,
    ];
    if (updated == null) return null;
    await _write(next);
    return updated;
  }

  /// Counts one geofence entry for the place. Missing places are ignored.
  Future<void> recordVisit(String id) async {
    final places = await _read();
    await _write([
      for (final p in places)
        if (p.id == id) p.copyWith(visitCount: p.visitCount + 1) else p,
    ]);
  }

  /// Deletes [id] only when it is temporary, so saved places are never lost by
  /// cancelling an alert.
  Future<void> removeIfTemporary(String id) async {
    final places = await _read();
    final next = [
      for (final p in places)
        if (!(p.id == id && p.temporary)) p,
    ];
    if (next.length != places.length) await _write(next);
  }

  /// Drops temporary places whose lifetime has passed.
  Future<void> purgeExpired() async {
    final now = _clock().toUtc();
    final places = await _read();
    final next = [
      for (final p in places)
        if (!p.isExpired(now)) p,
    ];
    if (next.length != places.length) await _write(next);
  }

  Future<void> remove(String id) async {
    final places = await _read();
    await _write([
      for (final p in places)
        if (p.id != id) p,
    ]);
  }

  /// Tags the user created, in creation order. Presets are not included.
  Future<List<PlaceTag>> customTags() async =>
      PlaceTag.decodeList(await _store.read(tagsStorageKey));

  Future<void> addCustomTag(PlaceTag tag) async {
    final tags = await customTags();
    if (tags.any((t) => t.name.toLowerCase() == tag.name.toLowerCase())) return;
    await _store.write(tagsStorageKey, PlaceTag.encodeList([...tags, tag]));
  }

  Future<void> clear() async {
    await _store.delete(storageKey);
    await _store.delete(tagsStorageKey);
    if (!_changes.isClosed) _changes.add(const []);
  }

  Future<List<SavedPlace>> _read() async =>
      SavedPlace.decodeList(await _store.read(storageKey));

  Future<void> _write(List<SavedPlace> places) async {
    await _store.write(storageKey, SavedPlace.encodeList(places));
    if (!_changes.isClosed) _changes.add(places);
  }

  void dispose() => _changes.close();
}
