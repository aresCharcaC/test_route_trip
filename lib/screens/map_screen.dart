import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trip_routing/trip_routing.dart';
import '../widgets/route_info_panel.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Controller para el mapa
  final MapController _mapController = MapController();

  // Servicio de rutas
  final TripService _tripService = TripService();

  // Estado de la ubicación y ruta
  LatLng? _currentPosition;
  LatLng? _startPoint;
  LatLng? _endPoint;
  List<LatLng> _routePoints = [];
  double _routeDistance = 0;

  // Estado de carga
  bool _isLoading = true;
  bool _isCalculatingRoute = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  // Obtener la ubicación actual del usuario
  Future<void> _getCurrentLocation() async {
    try {
      // Verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Permisos denegados
          setState(() => _isLoading = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // Permisos denegados permanentemente
        setState(() => _isLoading = false);
        return;
      }

      // Obtener posición
      Position position = await Geolocator.getCurrentPosition();

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });

      // Centrar mapa en la posición actual
      _mapController.move(_currentPosition!, 15);
    } catch (e) {
      print("Error getting location: $e");
      setState(() => _isLoading = false);
    }
  }

  // Calcular ruta entre puntos
  Future<void> _calculateRoute() async {
    if (_startPoint == null || _endPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Selecciona puntos de inicio y destino")),
      );
      return;
    }

    setState(() => _isCalculatingRoute = true);

    try {
      final trip = await _tripService.findTotalTrip(
        [_startPoint!, _endPoint!],
        preferWalkingPaths: true,
        replaceWaypointsWithBuildingEntrances: true,
      );

      setState(() {
        _routePoints = trip.route;
        _routeDistance = trip.distance;
        _isCalculatingRoute = false;
      });

      // Ajustar zoom para mostrar toda la ruta
      _fitRouteBounds();
    } catch (e) {
      print("Error calculating route: $e");
      setState(() => _isCalculatingRoute = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error al calcular la ruta: $e")));
    }
  }

  // Ajustar el mapa para mostrar toda la ruta
  void _fitRouteBounds() {
    if (_routePoints.isEmpty) return;

    // Crear un límite que contenga todos los puntos de la ruta
    var bounds = LatLngBounds.fromPoints(_routePoints);

    // Añadir un poco de padding
    final centerLat = bounds.center.latitude;
    final centerLng = bounds.center.longitude;
    final latDiff = (bounds.north - bounds.south) * 0.3; // 30% de padding
    final lngDiff = (bounds.east - bounds.west) * 0.3;

    // Crear nuevos límites con padding
    bounds = LatLngBounds(
      LatLng(bounds.south - latDiff, bounds.west - lngDiff),
      LatLng(bounds.north + latDiff, bounds.east + lngDiff),
    );

    // Usar el método actual para ajustar la vista
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)),
    );
  }

  // Limpiar ruta actual
  void _clearRoute() {
    setState(() {
      _startPoint = null;
      _endPoint = null;
      _routePoints = [];
      _routeDistance = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Router'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                children: [
                  // El mapa
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          _currentPosition ??
                          const LatLng(
                            -16.4090,
                            -71.5375,
                          ), // Arequipa por defecto
                      initialZoom: 15.0,
                      onTap: (_, point) {
                        // Alternar entre punto inicial y final
                        setState(() {
                          if (_startPoint == null) {
                            _startPoint = point;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Punto de inicio seleccionado"),
                              ),
                            );
                          } else if (_endPoint == null) {
                            _endPoint = point;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Punto de destino seleccionado"),
                              ),
                            );
                            // Ya no calculamos la ruta automáticamente
                          } else {
                            // Si ya hay dos puntos, empezar de nuevo
                            _startPoint = point;
                            _endPoint = null;
                            _routePoints = [];
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Nuevo punto de inicio seleccionado",
                                ),
                              ),
                            );
                          }
                        });
                      },
                    ),
                    children: [
                      // Capa de mapa base
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.test_trip_routing',
                      ),

                      // Capa de marcadores
                      MarkerLayer(
                        markers: [
                          // Marcador de posición actual
                          if (_currentPosition != null)
                            Marker(
                              point: _currentPosition!,
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.blue,
                                size: 30,
                              ),
                            ),

                          // Marcador de punto inicial
                          if (_startPoint != null)
                            Marker(
                              point: _startPoint!,
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.trip_origin,
                                color: Colors.green,
                                size: 30,
                              ),
                            ),

                          // Marcador de punto final
                          if (_endPoint != null)
                            Marker(
                              point: _endPoint!,
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.place,
                                color: Colors.red,
                                size: 30,
                              ),
                            ),
                        ],
                      ),

                      // Capa de ruta
                      if (_routePoints.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints,
                              strokeWidth: 4.0,
                              color: Colors.blue,
                            ),
                          ],
                        ),
                    ],
                  ),

                  // Indicador de carga durante el cálculo de ruta
                  if (_isCalculatingRoute)
                    const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text("Calculando ruta..."),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Panel de información de ruta
                  if (_routePoints.isNotEmpty)
                    RouteInfoPanel(
                      distance: _routeDistance,
                      onClear: _clearRoute,
                    ),

                  // Panel con botón calcular ruta cuando tengamos inicio y destino
                  if (_startPoint != null &&
                      _endPoint != null &&
                      _routePoints.isEmpty)
                    Positioned(
                      bottom: 20,
                      left: 20,
                      right: 20,
                      child: Card(
                        color: Colors.white,
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                "Puntos seleccionados",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Inicio: ${_startPoint!.latitude.toStringAsFixed(6)}, ${_startPoint!.longitude.toStringAsFixed(6)}",
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                "Destino: ${_endPoint!.latitude.toStringAsFixed(6)}, ${_endPoint!.longitude.toStringAsFixed(6)}",
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _clearRoute,
                                    icon: const Icon(Icons.clear),
                                    label: const Text("Borrar"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade100,
                                      foregroundColor: Colors.red.shade800,
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: _calculateRoute,
                                    icon: const Icon(Icons.directions),
                                    label: const Text("Calcular Ruta"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade100,
                                      foregroundColor: Colors.blue.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),

      // Botón para centrar en la ubicación actual
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_currentPosition != null) {
            _mapController.move(_currentPosition!, 15);
          }
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }
}
