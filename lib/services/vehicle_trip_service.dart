import 'package:trip_routing/trip_routing.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:trip_routing/src/utils/haversine.dart';

class VehicleTripService extends TripService {
  VehicleTripService() : super();

  // Sobreescribimos el método que hace la consulta a Overpass API para filtrar solo calles de vehículos
  @override
  Future<List<Map<String, dynamic>>> _fetchWalkingPaths(
    double minLat,
    double minLon,
    double maxLat,
    double maxLon,
  ) async {
    // Clamp bounds to avoid NaN/Infinity
    double clamp(double v, double min, double max) =>
        v.isFinite ? v.clamp(min, max) as double : min;
    minLat = clamp(minLat, -90, 90);
    maxLat = clamp(maxLat, -90, 90);
    minLon = clamp(minLon, -180, 180);
    maxLon = clamp(maxLon, -180, 180);

    // Nueva consulta Overpass modificada para vehículos
    // Incluimos solo vías que permitan vehículos y excluimos explícitamente las peatonales
    final query = '''
      [out:json];
      (
        // Incluir SOLO vías para vehículos
        way["highway"~"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|service)\$"]
           ["motor_vehicle"!="no"]
           ["foot"!="designated"]
           ["highway"!="pedestrian"]
           ["highway"!="footway"]
           ["highway"!="path"]
           ["highway"!="steps"]
           ["area"!="yes"]
           ["place"!="square"]
           ($minLat, $minLon, $maxLat, $maxLon);
      );
      out body;
      >;
      out skel qt;
      ''';

    final url = Uri.parse('https://overpass-api.de/api/interpreter');
    try {
      final response = await http.post(url, body: {'data': query});
      if (response.statusCode == 200) {
        final rawData = jsonDecode(response.body) as Map<String, dynamic>;
        final elements = rawData['elements'];
        if (elements is List) {
          return elements.map<Map<String, dynamic>>((e) {
            // Defensive extraction
            double safeDouble(dynamic v) {
              if (v is num && v.isFinite) return v.toDouble();
              if (v is String) {
                final d = double.tryParse(v);
                if (d != null && d.isFinite) return d;
              }
              return 0.0;
            }

            int safeInt(dynamic v) {
              if (v is int) return v;
              if (v is num && v.isFinite) return v.round();
              if (v is String) {
                final i = int.tryParse(v);
                if (i != null) return i;
              }
              return -1;
            }

            return {
              'type': e['type'] ?? '',
              'id': safeInt(e['id']),
              'lat': safeDouble(e['lat']),
              'lon': safeDouble(e['lon']),
              'tags': e['tags'] ?? <String, dynamic>{},
              'nodes':
                  (e['nodes'] is List)
                      ? List<int>.from(e['nodes'].map(safeInt))
                      : <int>[],
            };
          }).toList();
        }
      }
    } catch (e) {
      print("Error en consulta Overpass: $e");
    }
    return [];
  }

  /// Verifica si un punto está en una carretera para vehículos
  Future<bool> isOnVehicleRoad(LatLng point) async {
    try {
      final query = '''
        [out:json];
        (
          // Buscar carreteras para vehículos cerca del punto
          way["highway"~"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|service)\$"]
             ["motor_vehicle"!="no"]
             ["foot"!="designated"]
             ["highway"!="pedestrian"]
             ["highway"!="footway"]
             ["highway"!="path"]
             (around:15, ${point.latitude}, ${point.longitude});
        );
        out body;
        ''';

      final url = Uri.parse('https://overpass-api.de/api/interpreter');
      final response = await http.post(url, body: {'data': query});

      if (response.statusCode == 200) {
        final rawData = jsonDecode(response.body) as Map<String, dynamic>;
        final elements = rawData['elements'] as List;

        // Si encontramos al menos una carretera para vehículos, el punto es válido
        return elements.isNotEmpty;
      }

      return false;
    } catch (e) {
      print("Error al verificar punto: $e");
      return false;
    }
  }

  /// Ajusta un punto al nodo de calle vehicular más cercana
  Future<LatLng> snapToVehicleRoad(LatLng point) async {
    try {
      // Primero verificamos si el punto ya está en una carretera para vehículos
      final bool isOnRoad = await isOnVehicleRoad(point);
      if (isOnRoad) {
        return point; // Si ya está en una carretera, no necesitamos ajustarlo
      }

      // Lista de radios de búsqueda (en metros) para intentar secuencialmente
      final List<int> searchRadii = [150, 300, 500, 800, 1200];

      // Intentar con cada radio hasta encontrar una calle
      for (final radius in searchRadii) {
        // Buscar el nodo de carretera vehicular más cercano con el radio actual
        final query = '''
        [out:json];
        (
          // Nodos que forman parte de calles para vehículos
          way["highway"~"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|service)\$"]
             ["motor_vehicle"!="no"]
             ["foot"!="designated"]
             ["highway"!="pedestrian"]
             ["highway"!="footway"]
             ["highway"!="path"]
             (around:$radius, ${point.latitude}, ${point.longitude});
          node(w);
        );
        out body;
        ''';

        final url = Uri.parse('https://overpass-api.de/api/interpreter');
        final response = await http.post(url, body: {'data': query});

        if (response.statusCode == 200) {
          final rawData = jsonDecode(response.body) as Map<String, dynamic>;
          final elements = rawData['elements'] as List;

          if (elements.isNotEmpty) {
            // Encontrar el nodo más cercano
            LatLng closestNode = point;
            double minDistance = double.infinity;

            for (final element in elements) {
              if (element['type'] == 'node' &&
                  element['lat'] != null &&
                  element['lon'] != null) {
                final nodeLat = element['lat'] as double;
                final nodeLon = element['lon'] as double;
                final nodePoint = LatLng(nodeLat, nodeLon);

                final distance = haversineDistance(
                  point.latitude,
                  point.longitude,
                  nodePoint.latitude,
                  nodePoint.longitude,
                );

                if (distance < minDistance) {
                  minDistance = distance;
                  closestNode = nodePoint;
                }
              }
            }

            // Si encontramos un nodo cercano, lo usamos
            if (minDistance < double.infinity) {
              print(
                "Punto ajustado a la carretera (distancia: ${minDistance.toStringAsFixed(2)}m, radio de búsqueda: ${radius}m)",
              );
              return closestNode;
            }
          }
        }

        // Si llegamos aquí, no encontramos nada con este radio, intentamos con el siguiente
        print(
          "No se encontró carretera en radio de ${radius}m, intentando con radio mayor...",
        );
      }

      // Si después de intentar con todos los radios no encontramos nada,
      // devolvemos el punto original y mostramos un mensaje de advertencia
      print(
        "ADVERTENCIA: No se pudo encontrar una calle cercana después de intentar con radios de hasta ${searchRadii.last}m",
      );
      return point;
    } catch (e) {
      print("Error al ajustar a calle: $e");
      return point;
    }
  }

  @override
  Future<Trip> findTotalTrip(
    List<LatLng> waypoints, {
    bool preferWalkingPaths = false, // Siempre false para vehículos
    bool replaceWaypointsWithBuildingEntrances =
        false, // No necesario para vehículos
    bool forceIncludeWaypoints =
        false, // No lo usaremos para evitar pasar por puntos no vehiculares
    double duplicationPenalty = 0.0,
  }) async {
    // Primero ajustamos todos los waypoints a carreteras para vehículos
    List<LatLng> vehicleWaypoints = [];
    for (final waypoint in waypoints) {
      final snappedPoint = await snapToVehicleRoad(waypoint);
      vehicleWaypoints.add(snappedPoint);
    }

    // Llamamos al método original pero con opciones optimizadas para vehículos
    return super.findTotalTrip(
      vehicleWaypoints,
      preferWalkingPaths:
          false, // Aseguramos que nunca prefiera caminos peatonales
      replaceWaypointsWithBuildingEntrances: false,
      forceIncludeWaypoints: false,
      duplicationPenalty: duplicationPenalty,
    );
  }
}
