import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import 'notificaciones_view.dart';

class _Sucursal {
  final String nombre;
  final String horario;
  final LatLng punto;
  double distancia = 0; // metros
  _Sucursal(this.nombre, this.horario, this.punto);
}

/// Mapa (OpenStreetMap, sin API key) con:
///  * Ubicación actual del usuario.
///  * Seguimiento en tiempo real con recorrido, distancia y velocidad.
///  * Sucursales cercanas recomendadas con "Cómo llegar".
class MapaView extends StatefulWidget {
  const MapaView({super.key});

  @override
  State<MapaView> createState() => _MapaViewState();
}

class _MapaViewState extends State<MapaView> {
  final MapController _mapCtrl = MapController();
  bool _mapaListo = false;

  Position? _posicion;
  String? _error;
  bool _cargando = true;
  bool _errorPermanente = false;

  StreamSubscription<Position>? _sub;
  bool _siguiendo = false;
  final List<LatLng> _recorrido = [];
  double _distancia = 0; // metros
  DateTime? _inicio;
  Timer? _reloj;

  List<_Sucursal> _sucursales = [];

  static const LatLng _cdmx = LatLng(19.4326, -99.1332); // si no hay ubicación

  @override
  void initState() {
    super.initState();
    _obtenerUbicacion();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reloj?.cancel();
    super.dispose();
  }

  Future<bool> _verificarPermisos() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() {
        _error = 'La ubicación del dispositivo está desactivada.';
        _errorPermanente = false;
      });
      return false;
    }
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied) {
      setState(() => _error = 'Necesitamos permiso de ubicación para mostrar el mapa.');
      return false;
    }
    if (permiso == LocationPermission.deniedForever) {
      setState(() {
        _error = 'El permiso de ubicación fue denegado permanentemente.';
        _errorPermanente = true;
      });
      return false;
    }
    return true;
  }

  Future<void> _obtenerUbicacion() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      if (!await _verificarPermisos()) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 20));
      _actualizarPosicion(pos, centrar: true);
      if (_sucursales.isEmpty) _generarSucursales(pos);
    } catch (e) {
      // Si tarda demasiado usamos la última conocida.
      final ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null) {
        _actualizarPosicion(ultima, centrar: true);
        if (_sucursales.isEmpty) _generarSucursales(ultima);
      } else {
        setState(() => _error = 'No se pudo obtener tu ubicación: $e');
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _actualizarPosicion(Position pos, {bool centrar = false}) {
    if (!mounted) return;
    setState(() {
      _posicion = pos;
      final punto = LatLng(pos.latitude, pos.longitude);
      if (_siguiendo) {
        if (_recorrido.isNotEmpty) {
          final ult = _recorrido.last;
          _distancia += Geolocator.distanceBetween(ult.latitude, ult.longitude, pos.latitude, pos.longitude);
        }
        _recorrido.add(punto);
      }
      for (final s in _sucursales) {
        s.distancia = Geolocator.distanceBetween(
            pos.latitude, pos.longitude, s.punto.latitude, s.punto.longitude);
      }
      _sucursales.sort((a, b) => a.distancia.compareTo(b.distancia));
    });
    if ((centrar || _siguiendo) && _mapaListo) {
      _mapCtrl.move(LatLng(pos.latitude, pos.longitude), centrar ? 16 : _mapCtrl.camera.zoom);
    }
  }

  /// Sucursales de ejemplo alrededor del usuario (para la demo).
  void _generarSucursales(Position pos) {
    LatLng desplazar(double metrosNorte, double metrosEste) {
      const r = 6378137.0;
      final dLat = metrosNorte / r * 180 / math.pi;
      final dLng = metrosEste / (r * math.cos(pos.latitude * math.pi / 180)) * 180 / math.pi;
      return LatLng(pos.latitude + dLat, pos.longitude + dLng);
    }

    _sucursales = [
      _Sucursal('Mi Tiendita · Centro', '9:00 – 21:00', desplazar(450, 300)),
      _Sucursal('Mi Tiendita · Plaza Norte', '10:00 – 22:00', desplazar(1200, -500)),
      _Sucursal('Mi Tiendita · Express', '24 horas', desplazar(-350, -650)),
      _Sucursal('Punto de entrega · Parque', '8:00 – 18:00', desplazar(-900, 800)),
    ];
    _actualizarPosicion(pos);
  }

  Future<void> _alternarSeguimiento() async {
    if (_siguiendo) {
      await _sub?.cancel();
      _reloj?.cancel();
      setState(() => _siguiendo = false);
      return;
    }
    if (!await _verificarPermisos()) return;
    setState(() {
      _siguiendo = true;
      _recorrido.clear();
      _distancia = 0;
      _inicio = DateTime.now();
      if (_posicion != null) _recorrido.add(LatLng(_posicion!.latitude, _posicion!.longitude));
    });
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3),
    ).listen(
      (pos) => _actualizarPosicion(pos),
      onError: (e) => setState(() => _error = 'Error de GPS: $e'),
    );
  }

  Future<void> _comoLlegar(_Sucursal s) async {
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${s.punto.latitude},${s.punto.longitude}&travelmode=walking');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el navegador de mapas.')));
    }
  }

  void _compartirUbicacion() {
    final p = _posicion;
    if (p == null) return;
    SharePlus.instance.share(ShareParams(
      text: '📍 Esta es mi ubicación: https://maps.google.com/?q=${p.latitude},${p.longitude}',
      subject: 'Mi ubicación',
    ));
  }

  String _formatoDistancia(double m) => m < 1000 ? '${m.toStringAsFixed(0)} m' : '${(m / 1000).toStringAsFixed(2)} km';

  String get _duracion {
    if (_inicio == null) return '0:00';
    final d = DateTime.now().difference(_inicio!);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final pos = _posicion;
    final centro = pos != null ? LatLng(pos.latitude, pos.longitude) : _cdmx;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📍 Mapa y ubicación'),
        actions: [
          IconButton(
            tooltip: 'Compartir mi ubicación',
            icon: Icon(Icons.share_location_rounded, color: AppTheme.darkPink),
            onPressed: pos == null ? null : _compartirUbicacion,
          ),
          const NotificacionesBoton(),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              backgroundColor: const Color(0xFFFFEBEE),
              content: Text(_error!),
              leading: const Icon(Icons.location_off_rounded, color: Colors.red),
              actions: [
                TextButton(
                  onPressed: () async {
                    if (_errorPermanente) {
                      await Geolocator.openAppSettings();
                    } else if (!await Geolocator.isLocationServiceEnabled()) {
                      await Geolocator.openLocationSettings();
                    }
                    _obtenerUbicacion();
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: centro,
                    initialZoom: pos != null ? 16 : 11,
                    onMapReady: () {
                      _mapaListo = true;
                      if (_posicion != null) {
                        _mapCtrl.move(LatLng(_posicion!.latitude, _posicion!.longitude), 16);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.flutter_app',
                    ),
                    if (_recorrido.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(points: List.of(_recorrido), strokeWidth: 5, color: AppTheme.darkPink),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final s in _sucursales)
                          Marker(
                            point: s.punto,
                            width: 44,
                            height: 44,
                            child: GestureDetector(
                              onTap: () => _detalleSucursal(s),
                              child: Icon(Icons.storefront_rounded, size: 36, color: AppTheme.darkPink),
                            ),
                          ),
                        if (pos != null)
                          Marker(
                            point: LatLng(pos.latitude, pos.longitude),
                            width: 28,
                            height: 28,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E88E5),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const Positioned(
                  left: 6,
                  bottom: 4,
                  child: Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: Colors.black54)),
                ),
                if (_cargando) const Center(child: CircularProgressIndicator()),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'centrar',
                    backgroundColor: Colors.white,
                    onPressed: _obtenerUbicacion,
                    child: Icon(Icons.my_location_rounded, color: AppTheme.darkPink),
                  ),
                ),
                if (_siguiendo)
                  Positioned(
                    left: 12,
                    right: 70,
                    top: 12,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _dato('Distancia', _formatoDistancia(_distancia)),
                            _dato('Tiempo', _duracion),
                            _dato('Velocidad', '${(((pos?.speed ?? 0) < 0 ? 0 : (pos?.speed ?? 0)) * 3.6).toStringAsFixed(1)} km/h'),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              children: [
                SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    style: _siguiendo
                        ? ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400)
                        : null,
                    onPressed: _cargando && pos == null ? null : _alternarSeguimiento,
                    icon: Icon(_siguiendo ? Icons.stop_rounded : Icons.directions_walk_rounded),
                    label: Text(_siguiendo ? 'Detener seguimiento' : 'Iniciar seguimiento en tiempo real'),
                  ),
                ),
                if (pos != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Tu ubicación: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} · precisión ±${pos.accuracy.toStringAsFixed(0)} m',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
                const SizedBox(height: 10),
                const Text('Sucursales cercanas (ejemplo)',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                const SizedBox(height: 6),
                if (_sucursales.isEmpty)
                  const Text('Activa tu ubicación para ver recomendaciones cercanas.',
                      style: TextStyle(color: AppTheme.textMuted)),
                for (final s in _sucursales)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.storefront_rounded, color: AppTheme.darkPink),
                      title: Text(s.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${_formatoDistancia(s.distancia)} · ${s.horario}'),
                      trailing: IconButton(
                        tooltip: 'Cómo llegar',
                        icon: Icon(Icons.directions_rounded, color: AppTheme.darkPink),
                        onPressed: () => _comoLlegar(s),
                      ),
                      onTap: () {
                        if (_mapaListo) _mapCtrl.move(s.punto, 16);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dato(String titulo, String valor) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(valor, style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkPink)),
          Text(titulo, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      );

  void _detalleSucursal(_Sucursal s) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.nombre, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkPink)),
            const SizedBox(height: 6),
            Text('A ${_formatoDistancia(s.distancia)} de ti · Horario ${s.horario}'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _comoLlegar(s);
                },
                icon: const Icon(Icons.directions_rounded),
                label: const Text('Cómo llegar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
