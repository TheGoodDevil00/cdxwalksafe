import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../domain/entities/route_path.dart';

class ApiClient {
  static const String _baseUrl = String.fromEnvironment('API_BASE_URL');

  Future<List<RoutePath>> getRoutes(LatLng start, LatLng end) async {
    final Uri uri = Uri.parse('$_baseUrl/route').replace(
      queryParameters: <String, String>{
        'start_lat': start.latitude.toString(),
        'start_lon': start.longitude.toString(),
        'end_lat': end.latitude.toString(),
        'end_lon': end.longitude.toString(),
      },
    );

    try {
      final http.Response response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final List<dynamic> pointsRaw = data['safest'] as List<dynamic>? ?? <dynamic>[];
        final List<LatLng> points = pointsRaw
            .whereType<Map>()
            .map(
              (p) => LatLng(
                (p['lat'] as num).toDouble(),
                (p['lon'] as num).toDouble(),
              ),
            )
            .toList(growable: false);

        if (points.isEmpty) {
          return <RoutePath>[];
        }

        return <RoutePath>[
          RoutePath(
            id: 'safest',
            points: points,
            totalDistance: 0,
            safetyScore: 0,
            riskSegments: const [],
          ),
        ];
      }
      return <RoutePath>[];
    } catch (_) {
      return <RoutePath>[];
    }
  }
}
