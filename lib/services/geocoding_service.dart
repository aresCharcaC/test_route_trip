import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class GeocodingService {
  static const String _nominatimBaseUrl = 'https://nominatim.openstreetmap.org';

  /// Obtiene el nombre de la calle/avenida desde coordenadas
  /// Completamente gratuito usando Nominatim de OpenStreetMap
  static Future<String> getAddressFromCoordinates(LatLng coordinates) async {
    try {
      final url = Uri.parse(
        '$_nominatimBaseUrl/reverse?format=json&lat=${coordinates.latitude}&lon=${coordinates.longitude}&zoom=18&addressdetails=1&accept-language=es',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'TripRouterApp/1.0', // Requerido por Nominatim
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['address'] != null) {
          final address = data['address'];

          // Priorizar diferentes tipos de vías
          String? streetName;

          // Buscar en orden de prioridad
          streetName =
              address['road'] ??
              address['street'] ??
              address['avenue'] ??
              address['highway'] ??
              address['pedestrian'] ??
              address['footway'];

          if (streetName != null) {
            // Agregar tipo de vía si está disponible
            String? houseNumber = address['house_number'];
            String? suburb =
                address['suburb'] ??
                address['neighbourhood'] ??
                address['district'];

            String result = streetName;

            // Agregar número si existe
            if (houseNumber != null) {
              result = '$streetName $houseNumber';
            }

            // Agregar barrio/zona si existe y es diferente
            if (suburb != null &&
                !result.toLowerCase().contains(suburb.toLowerCase())) {
              result = '$result, $suburb';
            }

            return result;
          }
        }

        // Si no encontramos calle específica, usar display_name simplificado
        if (data['display_name'] != null) {
          String displayName = data['display_name'];
          // Tomar solo la primera parte (generalmente la más relevante)
          List<String> parts = displayName.split(',');
          if (parts.isNotEmpty) {
            return parts[0].trim();
          }
        }
      }
    } catch (e) {
      print('Error en geocodificación: $e');
    }

    // Fallback: mostrar coordenadas formateadas
    return 'Lat: ${coordinates.latitude.toStringAsFixed(6)}, Lng: ${coordinates.longitude.toStringAsFixed(6)}';
  }

  /// Versión más específica para obtener solo el nombre de la calle
  static Future<String> getStreetName(LatLng coordinates) async {
    try {
      final url = Uri.parse(
        '$_nominatimBaseUrl/reverse?format=json&lat=${coordinates.latitude}&lon=${coordinates.longitude}&zoom=18&addressdetails=1&accept-language=es&extratags=1',
      );

      final response = await http.get(
        url,
        headers: {'User-Agent': 'TripRouterApp/1.0'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['address'] != null) {
          final address = data['address'];

          // Solo el nombre de la calle, sin números ni detalles extra
          String? streetName =
              address['road'] ??
              address['street'] ??
              address['avenue'] ??
              address['highway'];

          if (streetName != null) {
            return streetName;
          }
        }
      }
    } catch (e) {
      print('Error obteniendo nombre de calle: $e');
    }

    return 'Ubicación seleccionada';
  }

  /// Obtiene una descripción corta y bonita del lugar
  static Future<String> getShortDescription(LatLng coordinates) async {
    try {
      final address = await getAddressFromCoordinates(coordinates);

      // Si es muy largo, acortarlo
      if (address.length > 50) {
        List<String> parts = address.split(',');
        if (parts.length > 1) {
          return parts[0].trim();
        }
      }

      return address;
    } catch (e) {
      return 'Ubicación seleccionada';
    }
  }
}
