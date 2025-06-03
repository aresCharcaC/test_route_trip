import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/vehicle_trip_service.dart';
import '../services/geocoding_service.dart'; // ← NUEVA IMPORTACIÓN
import '../widgets/route_info_panel.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Controller para el mapa
  final MapController _mapController = MapController();

  // Servicio de rutas para vehículos
  final VehicleTripService _tripService = VehicleTripService();

  // Estado de la ubicación y ruta
  LatLng? _currentPosition;
  LatLng? _startPoint;
  LatLng? _endPoint;
  List<LatLng> _routePoints = [];
  double _routeDistance = 0;

  // ← NUEVAS VARIABLES PARA NOMBRES DE CALLES
  String _startPointName = '';
  String _endPointName = '';
  bool _isLoadingStartName = false;
  bool _isLoadingEndName = false;

  // Estado de carga
  bool _isLoading = true;
  bool _isCalculatingRoute = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  // ← NUEVO MÉTODO PARA ACTUALIZAR NOMBRES
  Future<void> _updatePointName(LatLng point, bool isStartPoint) async {
    setState(() {
      if (isStartPoint) {
        _isLoadingStartName = true;
      } else {
        _isLoadingEndName = true;
      }
    });

    try {
      final name = await GeocodingService.getShortDescription(point);
      setState(() {
        if (isStartPoint) {
          _startPointName = name;
          _isLoadingStartName = false;
        } else {
          _endPointName = name;
          _isLoadingEndName = false;
        }
      });
    } catch (e) {
      setState(() {
        if (isStartPoint) {
          _startPointName = 'Ubicación de inicio';
          _isLoadingStartName = false;
        } else {
          _endPointName = 'Ubicación de destino';
          _isLoadingEndName = false;
        }
      });
    }
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
      // Verificar si los puntos están en carreteras para vehículos
      final bool startIsValid = await _tripService.isOnVehicleRoad(
        _startPoint!,
      );
      final bool endIsValid = await _tripService.isOnVehicleRoad(_endPoint!);

      // Si alguno no está en carretera, mostramos un mensaje y ajustamos los puntos
      if (!startIsValid || !endIsValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Algunos puntos no están en calles para vehículos. Ajustando a la calle más cercana.",
            ),
            duration: Duration(seconds: 3),
          ),
        );

        // Ajustar los puntos a carreteras para vehículos
        final LatLng snappedStart = await _tripService.snapToVehicleRoad(
          _startPoint!,
        );
        final LatLng snappedEnd = await _tripService.snapToVehicleRoad(
          _endPoint!,
        );

        // Actualizar los marcadores en el mapa Y los nombres
        setState(() {
          _startPoint = snappedStart;
          _endPoint = snappedEnd;
        });

        // ← ACTUALIZAR NOMBRES DESPUÉS DEL AJUSTE
        _updatePointName(snappedStart, true);
        _updatePointName(snappedEnd, false);
      }

      // Ahora calcular la ruta
      final trip = await _tripService.findTotalTrip(
        [_startPoint!, _endPoint!],
        preferWalkingPaths: false,
        replaceWaypointsWithBuildingEntrances: false,
      );

      setState(() {
        _routePoints = trip.route;
        _routeDistance = trip.distance;
        _isCalculatingRoute = false;
      });

      // Ajustar zoom para mostrar toda la ruta
      _fitRouteBounds();

      if (trip.route.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "No se pudo encontrar una ruta viable para vehículos",
            ),
          ),
        );
      }
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
      // ← LIMPIAR TAMBIÉN LOS NOMBRES
      _startPointName = '';
      _endPointName = '';
    });
  }

  // ← NUEVO WIDGET MEJORADO PARA MOSTRAR INFORMACIÓN DE PUNTOS
  Widget _buildPointInfoPanel() {
    if (_startPoint != null && _endPoint != null && _routePoints.isEmpty) {
      return Positioned(
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
                  "Ruta Seleccionada",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 12),

                // Punto de inicio con icono y nombre
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.trip_origin,
                        color: Colors.green.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Desde:",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                            _isLoadingStartName
                                ? const Row(
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text("Obteniendo dirección..."),
                                  ],
                                )
                                : Text(
                                  _startPointName.isNotEmpty
                                      ? _startPointName
                                      : "Cargando dirección...",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Punto de destino con icono y nombre
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.place, color: Colors.red.shade700, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Hasta:",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                            _isLoadingEndName
                                ? const Row(
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text("Obteniendo dirección..."),
                                  ],
                                )
                                : Text(
                                  _endPointName.isNotEmpty
                                      ? _endPointName
                                      : "Cargando dirección...",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Nota informativa
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "Los puntos se ajustarán a la calle para vehículos más cercana",
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Botones de acción
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _clearRoute,
                        icon: const Icon(Icons.clear, size: 18),
                        label: const Text("Borrar"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade100,
                          foregroundColor: Colors.red.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _calculateRoute,
                        icon: const Icon(Icons.directions, size: 18),
                        label: const Text("Calcular Ruta"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade100,
                          foregroundColor: Colors.blue.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Router para Mototaxis'),
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
                        // ← MODIFICADO PARA INCLUIR ACTUALIZACIÓN DE NOMBRES
                        setState(() {
                          if (_startPoint == null) {
                            _startPoint = point;
                            _updatePointName(point, true); // ← NUEVA LÍNEA
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Punto de inicio seleccionado"),
                              ),
                            );
                          } else if (_endPoint == null) {
                            _endPoint = point;
                            _updatePointName(point, false); // ← NUEVA LÍNEA
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Punto de destino seleccionado"),
                              ),
                            );
                          } else {
                            // Si ya hay dos puntos, empezar de nuevo
                            _startPoint = point;
                            _endPoint = null;
                            _routePoints = [];
                            _startPointName = '';
                            _endPointName = '';
                            _updatePointName(point, true); // ← NUEVA LÍNEA
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

                  // ← REEMPLAZAR EL PANEL ANTERIOR CON EL NUEVO
                  _buildPointInfoPanel(),
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
