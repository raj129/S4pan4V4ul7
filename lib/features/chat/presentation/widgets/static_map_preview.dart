import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:photo_vault/core/location/maps/google_api_auth.dart';
import '../../domain/entities/geo_share.dart';

/// Cached Google Static Maps screenshot preview for a pin, route, or arrival
/// alert card. Never instantiates a live [GoogleMap] widget.
class StaticMapPreview extends StatefulWidget {
  const StaticMapPreview({
    super.key,
    required this.share,
    this.height = 128,
    this.fallback,
  });

  final GeoShare share;
  final double height;
  final Widget? fallback;

  @override
  State<StaticMapPreview> createState() => _StaticMapPreviewState();
}

class _StaticMapPreviewState extends State<StaticMapPreview> {
  String? _apiKey;
  Map<String, String> _identityHeaders = const {};

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      unawaited(_loadAuth());
    }
  }

  Future<void> _loadAuth() async {
    final key = await GoogleApiAuth.instance.key;
    final headers = await GoogleApiAuth.instance.identityHeaders();
    if (!mounted || key.isEmpty) return;
    setState(() {
      _apiKey = key;
      _identityHeaders = headers;
    });
  }

  String _buildUrl(String apiKey) {
    final share = widget.share;
    final lat = share.point.latitude.toStringAsFixed(4);
    final lng = share.point.longitude.toStringAsFixed(4);
    final query = <String, dynamic>{
      'size': '512x256',
      'scale': '2',
      'key': apiKey,
    };
    if (share.isRoute && share.destination != null) {
      final dLat = share.destination!.latitude.toStringAsFixed(4);
      final dLng = share.destination!.longitude.toStringAsFixed(4);
      final pts = share.path.isEmpty
          ? [share.point, share.destination!]
          : _downsample(share.path, 24);
      final pathStr = pts
          .map(
            (p) =>
                '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}',
          )
          .join('|');
      query['markers'] = [
        'color:green|label:A|$lat,$lng',
        'color:red|label:B|$dLat,$dLng',
      ];
      query['path'] = 'color:0x1A73E8FF|weight:4|$pathStr';
    } else {
      final color = share.kind == GeoShareKind.arrival ? 'green' : 'red';
      query['center'] = '$lat,$lng';
      query['zoom'] = '15';
      query['markers'] = 'color:$color|$lat,$lng';
    }
    return Uri.https(
      'maps.googleapis.com',
      '/maps/api/staticmap',
      query,
    ).toString();
  }

  static List<GeoPoint> _downsample(List<GeoPoint> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final result = <GeoPoint>[points.first];
    final step = (points.length - 1) / (maxPoints - 1);
    for (var i = 1; i < maxPoints - 1; i++) {
      result.add(points[(i * step).round()]);
    }
    result.add(points.last);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback =
        widget.fallback ??
        Container(
          height: widget.height,
          width: double.infinity,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          alignment: Alignment.center,
          child: Icon(
            widget.share.isRoute ? Icons.alt_route_rounded : Icons.map_outlined,
            size: 32,
            color: cs.onSurfaceVariant,
          ),
        );

    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return fallback;

    final share = widget.share;
    final url = _buildUrl(apiKey);
    final cacheKey = share.isRoute && share.destination != null
        ? 'static_route_${share.point.latitude.toStringAsFixed(3)}_'
              '${share.point.longitude.toStringAsFixed(3)}_'
              '${share.destination!.latitude.toStringAsFixed(3)}_'
              '${share.destination!.longitude.toStringAsFixed(3)}'
        : 'static_pin_${share.kind.name}_'
              '${share.point.latitude.toStringAsFixed(4)}_'
              '${share.point.longitude.toStringAsFixed(4)}';

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: _identityHeaders,
        cacheKey: cacheKey,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
