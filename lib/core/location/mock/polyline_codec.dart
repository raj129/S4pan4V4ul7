import '../geo_fix.dart';

/// Google encoded polyline codec (precision 5).
class PolylineCodec {
  const PolylineCodec._();

  static List<GeoCoord> decode(String encoded) {
    final points = <GeoCoord>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    int next() {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    }

    while (index < encoded.length) {
      lat += next();
      lng += next();
      points.add(GeoCoord(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
