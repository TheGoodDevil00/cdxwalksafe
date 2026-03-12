import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../domain/entities/route_path.dart';

class ApiClient {
  // Use localhost for Android emulator (10.0.2.2) or local IP for real device
  // For Windows development, localhost is fine
  static const String baseUrl = 'http://localhost:8000/api/v1';

  Future<List<RoutePath>> getRoutes(LatLng start, LatLng end) async {
    final uri = Uri.parse('$baseUrl/route').replace(
      queryParameters: {
        'start_lat': start.latitude.toString(),
        'start_lon': start.longitude.toString(),
        'end_lat': end.latitude.toString(),
        'end_lon': end.longitude.toString(),
      },
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        List<RoutePath> routes = [];
        data.forEach((key, value) {
          // value is a list of points [{"lat":...}]
          List<LatLng> points = (value as List)
              .map((p) => LatLng(p['lat'], p['lon']))
              .toList();

          // Mocking risk segments for now
          routes.add(
            RoutePath(
              id: key,
              points: points,
              totalDistance: 0, //todo calc
              safetyScore: key == 'safest' ? 0.9 : 0.5,
              riskSegments: [],
            ),
          );
        });
        return routes;
      }
      return [];
    } catch (_) {
      // Return empty or cached routes
      return [];
    }
  }
}
