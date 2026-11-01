import 'package:flutter/material.dart';

import '../../application/services/saved_places_service.dart';
import '../../domain/entities/place_tag.dart';
import '../../domain/entities/saved_place.dart';
import '../screens/location_picker_screen.dart';

/// What the user chose for a place: its tag, and whether to keep it.
class PlaceOptions {
  const PlaceOptions({required this.keep, this.tag});

  final bool keep;
  final PlaceTag? tag;
}

/// Asks for a tag and whether to save a place. Returns null when dismissed.
/// The radius is chosen on the map, see `LocationPickerScreen`.
///
/// [keepByDefault] is false for places made from the arrival option, which are
/// temporary unless the user chooses to keep them.
Future<PlaceOptions?> pickPlaceOptions(
  BuildContext context, {
  required SavedPlacesService places,
  bool keepByDefault = true,
  bool showKeep = true,
}) async {
  final customTags = await places.customTags();
  if (!context.mounted) return null;
  return showModalBottomSheet<PlaceOptions>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _PlaceOptionsSheet(
      keepByDefault: keepByDefault,
      showKeep: showKeep,
      customTags: customTags,
      places: places,
    ),
  );
}

class _PlaceOptionsSheet extends StatefulWidget {
  const _PlaceOptionsSheet({
    required this.keepByDefault,
    required this.showKeep,
    required this.customTags,
    required this.places,
  });

  final bool keepByDefault;
  final bool showKeep;
  final List<PlaceTag> customTags;
  final SavedPlacesService places;

  @override
  State<_PlaceOptionsSheet> createState() => _PlaceOptionsSheetState();
}

class _PlaceOptionsSheetState extends State<_PlaceOptionsSheet> {
  late bool _keep = widget.keepByDefault;
  late List<PlaceTag> _customTags = widget.customTags;
  PlaceTag? _tag;

  Future<void> _newTag() async {
    final created = await showDialog<PlaceTag>(
      context: context,
      builder: (_) => const _NewTagDialog(),
    );
    if (created == null) return;
    await widget.places.addCustomTag(created);
    if (!mounted) return;
    setState(() {
      _customTags = [..._customTags, created];
      _tag = created;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tags = [...PlaceTag.presets, ..._customTags];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tag'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      radius: 6,
                      backgroundColor: Color(tag.color),
                    ),
                    label: Text(tag.name),
                    selected: _tag == tag,
                    onSelected: (_) => setState(() => _tag = tag),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('New tag'),
                  onPressed: _newTag,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.showKeep)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Save this place'),
                subtitle: const Text(
                  'Off: the place is removed after the alert fires or is cancelled.',
                ),
                value: _keep,
                onChanged: (v) => setState(() => _keep = v),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, PlaceOptions(keep: _keep, tag: _tag)),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewTagDialog extends StatefulWidget {
  const _NewTagDialog();

  @override
  State<_NewTagDialog> createState() => _NewTagDialogState();
}

class _NewTagDialogState extends State<_NewTagDialog> {
  final _name = TextEditingController();
  int _color = PlaceTag.paletteColors.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(labelText: 'Tag name'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              for (final c in PlaceTag.paletteColors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(c),
                    child: _color == c
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, PlaceTag(name: name, color: _color));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Picks a point and radius on the map, then tag and save option, and saves a
/// new place. Returns the saved place, or null when cancelled.
Future<SavedPlace?> addSavedPlace(
  BuildContext context, {
  required SavedPlacesService places,
  required String ownerUid,
  required List<SavedPlace> existing,
  bool keepByDefault = true,
}) async {
  final pick = await Navigator.of(context).push<ArrivalPlacePick>(
    MaterialPageRoute(
      builder: (_) => LocationPickerScreen(
        allowRoute: false,
        requireLabel: true,
        title: 'Add place',
        confirmLabel: 'Save place',
        showRadius: true,
        savedPlaces: existing,
      ),
    ),
  );
  if (pick == null || !context.mounted) return null;
  final options = await pickPlaceOptions(
    context,
    places: places,
    keepByDefault: keepByDefault,
  );
  if (options == null) return null;
  return places.add(
    ownerUid: ownerUid,
    label: pick.share.label,
    point: pick.share.point,
    radiusMeters: pick.radiusMeters,
    tag: options.tag,
    temporary: !options.keep,
  );
}

/// Lets the user move a saved place, change its radius, and change its tag.
Future<void> editSavedPlace(
  BuildContext context, {
  required SavedPlacesService places,
  required SavedPlace place,
  required List<SavedPlace> others,
}) async {
  final pick = await Navigator.of(context).push<ArrivalPlacePick>(
    MaterialPageRoute(
      builder: (_) => LocationPickerScreen(
        allowRoute: false,
        requireLabel: true,
        title: 'Edit place',
        confirmLabel: 'Save changes',
        showRadius: true,
        initialRadius: place.radiusMeters,
        initialPin: place.point,
        initialLabel: place.label,
        savedPlaces: others,
      ),
    ),
  );
  if (pick == null || !context.mounted) return;
  final options = await pickPlaceOptions(
    context,
    places: places,
    showKeep: false,
  );
  if (options == null) return;
  await places.update(
    place.id,
    label: pick.share.label,
    point: pick.share.point,
    radiusMeters: pick.radiusMeters,
    tag: options.tag,
    clearTag: options.tag == null,
  );
}

/// Result of [pickSavedPlace]: either an existing place, or a request for a new one.
class PlacePick {
  const PlacePick.saved(this.place) : isNew = false;
  const PlacePick.newPlace() : place = null, isNew = true;

  final SavedPlace? place;
  final bool isNew;
}

/// Lists the owner's places, most visited first, for `/arrive`.
Future<PlacePick?> pickSavedPlace(
  BuildContext context, {
  required List<SavedPlace> places,
}) {
  return showModalBottomSheet<PlacePick>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Tell on arrival at'),
          ),
          for (final place in places)
            ListTile(
              leading: CircleAvatar(
                radius: 8,
                backgroundColor: Color(place.tagColor ?? 0xFF757575),
              ),
              title: Text(place.label),
              subtitle: Text(
                '${place.tagName ?? 'No tag'} - ${place.radiusMeters.round()} m'
                '${place.visitCount > 0 ? ' - visited ${place.visitCount}x' : ''}',
              ),
              onTap: () => Navigator.pop(sheetContext, PlacePick.saved(place)),
            ),
          ListTile(
            leading: const Icon(Icons.add_location_alt_rounded),
            title: const Text('New place'),
            onTap: () =>
                Navigator.pop(sheetContext, const PlacePick.newPlace()),
          ),
        ],
      ),
    ),
  );
}
