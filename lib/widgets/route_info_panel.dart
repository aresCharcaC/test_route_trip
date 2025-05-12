import 'package:flutter/material.dart';

class RouteInfoPanel extends StatelessWidget {
  final double distance;
  final VoidCallback onClear;

  const RouteInfoPanel({
    super.key,
    required this.distance,
    required this.onClear,
  });

  // Convertir distancia a formato legible
  String _formatDistance() {
    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)} metros';
    } else {
      return '${(distance / 1000).toStringAsFixed(2)} km';
    }
  }

  // Calcular tiempo estimado (asumiendo 5km/h para caminar)
  // Calcular tiempo estimado para mototaxi (velocidad promedio 30 km/h)
  String _estimateTime() {
    // 30 km/h = 500 metros por minuto
    final minutes = distance / 500;

    if (minutes < 1) {
      return '< 1 minuto';
    } else if (minutes < 60) {
      return '${minutes.toStringAsFixed(0)} minutos';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = (minutes % 60).toInt();
      return '$hours h ${remainingMinutes} min';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Información de Ruta',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: onClear),
              ],
            ),
            const Divider(),
            Row(
              children: [
                const Icon(Icons.straighten, color: Colors.blue),
                const SizedBox(width: 8),
                Text('Distancia: ${_formatDistance()}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.timer, color: Colors.blue),
                const SizedBox(width: 8),
                Text('Tiempo estimado: ${_estimateTime()}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
