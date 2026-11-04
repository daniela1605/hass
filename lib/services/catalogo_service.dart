import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../repository/database_helper.dart';

class ResultadoCatalogo {
  final List<Map<String, dynamic>> productos;
  final bool offline;
  final DateTime? ultimaSincronizacion;
  ResultadoCatalogo(this.productos, this.offline, this.ultimaSincronizacion);
}

/// Catálogo con soporte offline: se descarga de la API cuando hay internet,
/// se guarda en SQLite y, sin conexión, se lee de la copia local.
class CatalogoService {
  CatalogoService._();
  static final CatalogoService instance = CatalogoService._();

  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<ResultadoCatalogo>? _enCurso;

  /// Si ya hay una carga en curso se reutiliza (evita duplicados en SQLite).
  Future<ResultadoCatalogo> cargar() {
    return _enCurso ??= _cargar().whenComplete(() => _enCurso = null);
  }

  Future<ResultadoCatalogo> _cargar() async {
    var offline = false;
    final prefs = await SharedPreferences.getInstance();
    try {
      final r = await http
          .get(Uri.parse(AppConfig.productosApiUrl))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final List<dynamic> data = jsonDecode(r.body);
      final eliminados = await _db.apiIdsEliminados();
      for (final item in data) {
        final apiId = item['id'] as int;
        if (eliminados.contains(apiId)) continue;
        await _db.upsertProductoApi(
          apiId: apiId,
          nombre: (item['title'] ?? 'Producto sin nombre').toString(),
          precio: (item['price'] as num?)?.toDouble() ?? 0.0,
          imagen: item['image']?.toString(),
          categoria: item['category']?.toString(),
          descripcion: item['description']?.toString(),
        );
      }
      await prefs.setString('catalogo_sync', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Sin conexión, usando catálogo local: $e');
      offline = true;
    }

    final filas = await _db.listarProductos();
    final productos = filas.map(aVista).toList();
    final sync = DateTime.tryParse(prefs.getString('catalogo_sync') ?? '');
    return ResultadoCatalogo(productos, offline, sync);
  }

  /// Convierte una fila de SQLite al mapa que usan las vistas.
  static Map<String, dynamic> aVista(Map<String, dynamic> f) => {
        'id': f['id'],
        'nombre_product': f['nombre'] ?? 'Producto',
        'precio': (f['precio'] as num?)?.toDouble() ?? 0.0,
        'cantidad': f['stock'] ?? 1000,
        'imagen': f['imagen'] ?? '',
        'categoria': f['categoria'] ?? 'General',
        'descripcion': f['descripcion'] ?? '',
        'origen': f['api_id'] == null ? 'local' : 'api',
      };

  // ─── Recomendaciones ───────────────────────────────────────────────────────

  /// Recomienda productos según el historial (compras, carrito y vistas).
  /// Devuelve la lista y si es personalizada (`true`) o de populares.
  Future<(List<Map<String, dynamic>>, bool)> recomendar(
      int usuarioId, List<Map<String, dynamic>> productos,
      {int max = 8}) async {
    if (productos.isEmpty) return (<Map<String, dynamic>>[], false);
    final puntajes = await _db.puntajesPorCategoria(usuarioId);
    final comprados = await _db.productosComprados(usuarioId);

    if (puntajes.isEmpty) {
      // Sin historial: los mejor valorados por precio dentro de cada categoría.
      final populares = [...productos]
        ..sort((a, b) => (b['precio'] as double).compareTo(a['precio'] as double));
      final porCategoria = <String>{};
      final lista = <Map<String, dynamic>>[];
      for (final p in populares) {
        if (porCategoria.add(p['categoria'] as String) || lista.length < 4) lista.add(p);
        if (lista.length >= max) break;
      }
      return (lista, false);
    }

    final candidatos = productos.where((p) => !comprados.contains(p['id'])).toList()
      ..sort((a, b) {
        final pa = puntajes[a['categoria']] ?? 0;
        final pb = puntajes[b['categoria']] ?? 0;
        if (pa != pb) return pb.compareTo(pa);
        return (a['precio'] as double).compareTo(b['precio'] as double);
      });
    return (candidatos.take(max).toList(), true);
  }
}
