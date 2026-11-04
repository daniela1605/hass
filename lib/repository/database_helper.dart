import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import '../models/usuario.dart';
import '../services/security_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  static const int _version = 6;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('seguridad.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(
      path,
      version: _version,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  // ─── ESQUEMA ───────────────────────────────────────────────────────────────

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE usuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        nombres TEXT,
        apellido_paterno TEXT,
        apellido_materno TEXT,
        email TEXT UNIQUE NOT NULL,
        username TEXT,
        password TEXT NOT NULL,
        rol TEXT NOT NULL CHECK (rol IN ('admin', 'editor', 'lector')),
        telefono TEXT,
        proveedor TEXT NOT NULL DEFAULT 'local',
        intentos_fallidos INTEGER NOT NULL DEFAULT 0,
        bloqueado_hasta TEXT
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_usuarios_username ON usuarios(username)');

    await db.execute('''
      CREATE TABLE productos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        precio REAL NOT NULL,
        stock INTEGER NOT NULL DEFAULT 1000,
        imagen TEXT,
        categoria TEXT DEFAULT 'General',
        descripcion TEXT,
        api_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE carrito (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        nombre TEXT NOT NULL,
        precio REAL NOT NULL,
        cantidad INTEGER NOT NULL,
        imagen TEXT,
        FOREIGN KEY(usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE historial_compras (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        productos_json TEXT NOT NULL,
        total REAL NOT NULL,
        fecha TEXT NOT NULL,
        transaction_id TEXT,
        metodo_pago TEXT,
        detalle_pago TEXT,
        estado_pago TEXT DEFAULT 'aprobado',
        FOREIGN KEY(usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE
      )
    ''');

    await _crearTablasV3(db);
    await _crearTablaGestoPago(db);

    // Usuarios de muestra (contraseñas con hash PBKDF2).
    // Sus correos/teléfonos se configuran en config/env.json (DEMO_*).
    final hash = await SecurityService.hashPassword('password123');
    for (final d in _usuariosDemo) {
      await db.insert('usuarios', {
        'nombre': Usuario.componerNombre(d.nombres, d.paterno, d.materno),
        'nombres': d.nombres,
        'apellido_paterno': d.paterno,
        'apellido_materno': d.materno,
        // Si en env.json la clave existe pero vacía, se usa el correo genérico.
        'email': (d.email.contains('@') ? d.email : '${d.username}@gmail.com').toLowerCase(),
        'username': d.username,
        'password': hash,
        'rol': d.rol,
        'telefono': SecurityService.cifrar(d.telefono),
      });
    }
  }

  static const _usuariosDemo = [
    (username: 'juan', nombres: 'Juan', paterno: 'Pérez', materno: 'Gómez', rol: 'admin', email: AppConfig.demoAdminEmail, telefono: AppConfig.demoAdminTelefono),
    (username: 'pedro', nombres: 'Pedro', paterno: 'López', materno: 'Ramírez', rol: 'editor', email: AppConfig.demoEditorEmail, telefono: AppConfig.demoEditorTelefono),
    (username: 'ana', nombres: 'Ana', paterno: 'García', materno: 'Torres', rol: 'lector', email: AppConfig.demoLectorEmail, telefono: AppConfig.demoLectorTelefono),
  ];

  /// Aplica a la BD ya existente los correos/teléfonos de los usuarios de
  /// prueba definidos en config/env.json. Se llama al iniciar la app.
  Future<void> sincronizarUsuariosDemo() async {
    final db = await instance.database;
    for (final d in _usuariosDemo) {
      final filas = await db.query('usuarios', where: 'LOWER(username) = ?', whereArgs: [d.username]);
      if (filas.isEmpty) continue;
      final actual = Usuario.fromMap(filas.first);
      final cambios = <String, Object?>{};
      final email = d.email.trim().toLowerCase();
      if (email.contains('@') && email != actual.email.toLowerCase()) {
        final ocupado = await db.query('usuarios',
            where: 'LOWER(email) = ? AND id != ?', whereArgs: [email, actual.id]);
        if (ocupado.isEmpty) cambios['email'] = email;
      }
      if (d.telefono.trim().isNotEmpty && d.telefono.trim() != actual.telefono) {
        cambios['telefono'] = SecurityService.cifrar(d.telefono.trim());
      }
      if (cambios.isNotEmpty) {
        await db.update('usuarios', cambios, where: 'id = ?', whereArgs: [actual.id]);
      }
    }
  }

  Future<void> _crearTablasV3(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notificaciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        titulo TEXT NOT NULL,
        cuerpo TEXT NOT NULL,
        tipo TEXT NOT NULL DEFAULT 'sistema',
        leida INTEGER NOT NULL DEFAULT 0,
        fecha TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS interacciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        fecha TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_productos_api ON productos(api_id)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('CREATE TABLE IF NOT EXISTS productos (id INTEGER PRIMARY KEY AUTOINCREMENT, nombre TEXT NOT NULL, precio REAL NOT NULL, stock INTEGER NOT NULL DEFAULT 1000, imagen TEXT)');
      await db.execute('CREATE TABLE IF NOT EXISTS carrito (id INTEGER PRIMARY KEY AUTOINCREMENT, usuario_id INTEGER NOT NULL, producto_id INTEGER NOT NULL, nombre TEXT NOT NULL, precio REAL NOT NULL, cantidad INTEGER NOT NULL, imagen TEXT)');
      await db.execute('CREATE TABLE IF NOT EXISTS historial_compras (id INTEGER PRIMARY KEY AUTOINCREMENT, usuario_id INTEGER NOT NULL, productos_json TEXT NOT NULL, total REAL NOT NULL, fecha TEXT NOT NULL, transaction_id TEXT)');
    }
    if (oldVersion < 3) {
      // Usuarios: nuevas columnas
      await db.execute('ALTER TABLE usuarios ADD COLUMN username TEXT');
      await db.execute('ALTER TABLE usuarios ADD COLUMN telefono TEXT');
      await db.execute("ALTER TABLE usuarios ADD COLUMN proveedor TEXT NOT NULL DEFAULT 'local'");
      await db.execute('ALTER TABLE usuarios ADD COLUMN intentos_fallidos INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE usuarios ADD COLUMN bloqueado_hasta TEXT');

      // Generar nombre de usuario único y migrar contraseñas a hash
      final usuarios = await db.query('usuarios');
      final usados = <String>{};
      for (final u in usuarios) {
        var base = (u['email'] as String).split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]'), '');
        if (base.isEmpty) base = 'usuario';
        var candidato = base;
        var n = 1;
        while (usados.contains(candidato)) {
          candidato = '$base${n++}';
        }
        usados.add(candidato);
        final pass = u['password'] as String;
        final hash = SecurityService.esHash(pass) ? pass : await SecurityService.hashPassword(pass);
        await db.update('usuarios', {'username': candidato, 'password': hash}, where: 'id = ?', whereArgs: [u['id']]);
      }
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_usuarios_username ON usuarios(username)');

      // Productos: nuevas columnas para modo offline y recomendaciones
      await db.execute("ALTER TABLE productos ADD COLUMN categoria TEXT DEFAULT 'General'");
      await db.execute('ALTER TABLE productos ADD COLUMN descripcion TEXT');
      await db.execute('ALTER TABLE productos ADD COLUMN api_id INTEGER');

      await _crearTablasV3(db);
    await _crearTablaGestoPago(db);
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE historial_compras ADD COLUMN metodo_pago TEXT');
      await db.execute('ALTER TABLE historial_compras ADD COLUMN detalle_pago TEXT');
      await db.execute("ALTER TABLE historial_compras ADD COLUMN estado_pago TEXT DEFAULT 'aprobado'");
    }
    if (oldVersion < 5) {
      // Nombre separado: nombres, apellido paterno y apellido materno.
      await db.execute('ALTER TABLE usuarios ADD COLUMN nombres TEXT');
      await db.execute('ALTER TABLE usuarios ADD COLUMN apellido_paterno TEXT');
      await db.execute('ALTER TABLE usuarios ADD COLUMN apellido_materno TEXT');
      final filas = await db.query('usuarios', columns: ['id', 'nombre']);
      for (final f in filas) {
        final (n, p, m) = Usuario.separarNombre(f['nombre'] as String? ?? '');
        await db.update('usuarios', {'nombres': n, 'apellido_paterno': p, 'apellido_materno': m},
            where: 'id = ?', whereArgs: [f['id']]);
      }
    }
    if (oldVersion < 6) {
      await _crearTablaGestoPago(db);
    }
  }

  Future<void> _crearTablaGestoPago(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS gestopago_catalogo (
        unique_key TEXT PRIMARY KEY,
        servicio TEXT NOT NULL,
        producto TEXT NOT NULL,
        id_servicio TEXT NOT NULL,
        id_producto TEXT NOT NULL,
        id_cat_tipo_servicio TEXT NOT NULL,
        tipo_front TEXT NOT NULL,
        has_digito_verificador INTEGER NOT NULL DEFAULT 0,
        precio REAL NOT NULL DEFAULT 0,
        show_ayuda INTEGER NOT NULL DEFAULT 0,
        tipo_referencia TEXT NOT NULL DEFAULT 'a',
        legend TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gestopago_cat ON gestopago_catalogo(id_cat_tipo_servicio)',
    );
  }

  // ─── GESTOPAGO CATÁLOGO (PERSISTENCIA SQLITE) ──────────────────────────────

  Future<void> guardarCatalogoGestoPago(List<Map<String, dynamic>> items) async {
    final db = await instance.database;
    await _crearTablaGestoPago(db);
    final batch = db.batch();
    for (final item in items) {
      batch.insert(
        'gestopago_catalogo',
        item,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> obtenerCatalogoGestoPago() async {
    final db = await instance.database;
    await _crearTablaGestoPago(db);
    return await db.query('gestopago_catalogo', orderBy: 'servicio ASC, precio ASC');
  }

  // ─── USUARIOS ──────────────────────────────────────────────────────────────

  Future<List<Usuario>> obtenerTodos() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT * FROM usuarios ORDER BY id ASC');
    return result.map((json) => Usuario.fromMap(json)).toList();
  }

  Future<Usuario?> obtenerPorId(int id) async {
    final db = await instance.database;
    final r = await db.query('usuarios', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Usuario.fromMap(r.first);
  }

  Future<Usuario?> obtenerPorEmail(String email) async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT * FROM usuarios WHERE LOWER(email) = LOWER(?)',
      [email.trim()],
    );
    if (result.isNotEmpty) return Usuario.fromMap(result.first);
    return null;
  }

  Future<Usuario?> obtenerPorUsername(String username) async {
    final db = await instance.database;
    final r = await db.rawQuery(
      'SELECT * FROM usuarios WHERE LOWER(username) = LOWER(?)',
      [username.trim()],
    );
    return r.isEmpty ? null : Usuario.fromMap(r.first);
  }

  /// Busca por correo o por nombre de usuario.
  Future<Usuario?> obtenerPorIdentificador(String identificador) async {
    final id = identificador.trim();
    if (id.contains('@')) return obtenerPorEmail(id);
    return obtenerPorUsername(id);
  }

  /// El teléfono está cifrado, así que se compara ya descifrado.
  Future<Usuario?> obtenerPorTelefono(String telefono) async {
    final buscado = _soloDigitos(telefono);
    if (buscado.length < 8) return null;
    for (final u in await obtenerTodos()) {
      final t = _soloDigitos(u.telefono);
      if (t.isNotEmpty && (t == buscado || t.endsWith(buscado) || buscado.endsWith(t))) {
        return u;
      }
    }
    return null;
  }

  String _soloDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  Future<int> insertar(Usuario usuario) async {
    final db = await instance.database;
    final map = usuario.toMap()..remove('id');
    return await db.insert('usuarios', map);
  }

  Future<int> eliminar(int id) async {
    final db = await instance.database;
    await db.delete('carrito', where: 'usuario_id = ?', whereArgs: [id]);
    await db.delete('notificaciones', where: 'usuario_id = ?', whereArgs: [id]);
    await db.delete('interacciones', where: 'usuario_id = ?', whereArgs: [id]);
    await db.delete('historial_compras', where: 'usuario_id = ?', whereArgs: [id]);
    return await db.rawDelete('DELETE FROM usuarios WHERE id = ?', [id]);
  }

  Future<int> actualizarRol(int id, String nuevoRol) async {
    final db = await instance.database;
    return await db.rawUpdate('UPDATE usuarios SET rol = ? WHERE id = ?', [nuevoRol, id]);
  }

  /// Guarda el hash de la nueva contraseña y desbloquea la cuenta.
  Future<int> actualizarPasswordHash(int id, String hash) async {
    final db = await instance.database;
    return await db.update(
      'usuarios',
      {'password': hash, 'intentos_fallidos': 0, 'bloqueado_hasta': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> registrarIntentoFallido(int id, int intentos, DateTime? bloqueadoHasta) async {
    final db = await instance.database;
    await db.update(
      'usuarios',
      {'intentos_fallidos': intentos, 'bloqueado_hasta': bloqueadoHasta?.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reiniciarIntentos(int id) async {
    final db = await instance.database;
    await db.update('usuarios', {'intentos_fallidos': 0, 'bloqueado_hasta': null},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> actualizarPerfil(
    int id, {
    required String nombres,
    required String apellidoPaterno,
    required String apellidoMaterno,
    required String telefono,
  }) async {
    final db = await instance.database;
    await db.update(
      'usuarios',
      {
        ..._camposNombre(nombres, apellidoPaterno, apellidoMaterno),
        'telefono': SecurityService.cifrar(telefono.trim()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Map<String, Object?> _camposNombre(String nombres, String paterno, String materno) => {
        'nombre': Usuario.componerNombre(nombres, paterno, materno),
        'nombres': nombres.trim(),
        'apellido_paterno': paterno.trim(),
        'apellido_materno': materno.trim(),
      };

  /// Edición completa de un usuario (solo administradores).
  Future<void> actualizarDatosUsuario(
    int id, {
    required String nombres,
    required String apellidoPaterno,
    required String apellidoMaterno,
    required String email,
    required String username,
    required String telefono,
    required String rol,
  }) async {
    final db = await instance.database;
    await db.update(
      'usuarios',
      {
        ..._camposNombre(nombres, apellidoPaterno, apellidoMaterno),
        'email': email.trim().toLowerCase(),
        'username': username.trim().toLowerCase(),
        'telefono': SecurityService.cifrar(telefono.trim()),
        'rol': rol,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> existeUsername(String username) async =>
      (await obtenerPorUsername(username)) != null;

  // ─── PRODUCTOS ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listarProductos() async {
    final db = await instance.database;
    // Primero los creados localmente (api_id NULL), luego los de la API.
    return await db.rawQuery('SELECT * FROM productos ORDER BY (api_id IS NOT NULL), id DESC');
  }

  Future<Map<String, dynamic>?> obtenerProducto(int id) async {
    final db = await instance.database;
    final r = await db.query('productos', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  /// Inserta o actualiza un producto que viene de la API (para uso offline).
  Future<void> upsertProductoApi({
    required int apiId,
    required String nombre,
    required double precio,
    String? imagen,
    String? categoria,
    String? descripcion,
  }) async {
    final db = await instance.database;
    final datos = {
      'nombre': nombre,
      'precio': precio,
      'imagen': imagen,
      'categoria': categoria ?? 'General',
      'descripcion': descripcion ?? '',
      'api_id': apiId,
    };
    var existente = await db.query('productos', columns: ['id'], where: 'api_id = ?', whereArgs: [apiId]);
    if (existente.isEmpty) {
      // Registros antiguos (v2) sin api_id: se enlazan por nombre.
      existente = await db.query('productos', columns: ['id'], where: 'api_id IS NULL AND nombre = ?', whereArgs: [nombre]);
    }
    if (existente.isEmpty) {
      await db.insert('productos', {...datos, 'stock': 1000});
    } else {
      await db.update('productos', datos, where: 'id = ?', whereArgs: [existente.first['id']]);
    }
  }

  /// Ids de la API que el usuario eliminó (para no volver a descargarlos).
  Future<Set<int>> apiIdsEliminados() async {
    final db = await instance.database;
    await db.execute('CREATE TABLE IF NOT EXISTS productos_eliminados (api_id INTEGER PRIMARY KEY)');
    final r = await db.query('productos_eliminados');
    return r.map((e) => e['api_id'] as int).toSet();
  }

  Future<int> insertarProducto(String nombre, double precio, String? imagen,
      {String categoria = 'General', String descripcion = ''}) async {
    final db = await instance.database;
    return await db.insert('productos', {
      'nombre': nombre,
      'precio': precio,
      'stock': 1000,
      'imagen': imagen,
      'categoria': categoria,
      'descripcion': descripcion,
    });
  }

  Future<int> eliminarProducto(int id) async {
    final db = await instance.database;
    final prod = await obtenerProducto(id);
    if (prod != null && prod['api_id'] != null) {
      await db.execute('CREATE TABLE IF NOT EXISTS productos_eliminados (api_id INTEGER PRIMARY KEY)');
      await db.insert('productos_eliminados', {'api_id': prod['api_id']},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return await db.delete('productos', where: 'id = ?', whereArgs: [id]);
  }

  // ─── CARRITO ───────────────────────────────────────────────────────────────

  Future<void> agregarAlCarrito(int usuarioId, Map<String, dynamic> item) async {
    final db = await instance.database;
    final existing = await db.rawQuery(
      'SELECT * FROM carrito WHERE usuario_id = ? AND producto_id = ?',
      [usuarioId, item['id']],
    );
    final String prodNombre = item['nombre_product']?.toString() ?? item['nombre']?.toString() ?? 'Producto';
    final double prodPrecio = item['precio'] is num ? (item['precio'] as num).toDouble() : double.tryParse(item['precio'].toString()) ?? 0.0;
    final int prodCantidad = item['cantidad'] is int ? item['cantidad'] as int : int.tryParse(item['cantidad'].toString()) ?? 1;
    final String? prodImagen = item['imagen']?.toString();

    if (existing.isNotEmpty) {
      await db.rawUpdate(
        'UPDATE carrito SET cantidad = cantidad + ? WHERE usuario_id = ? AND producto_id = ?',
        [prodCantidad, usuarioId, item['id']],
      );
    } else {
      await db.insert('carrito', {
        'usuario_id': usuarioId,
        'producto_id': item['id'],
        'nombre': prodNombre,
        'precio': prodPrecio,
        'cantidad': prodCantidad,
        'imagen': prodImagen,
      });
    }
  }

  Future<List<Map<String, dynamic>>> obtenerCarrito(int usuarioId) async {
    final db = await instance.database;
    return await db.rawQuery('SELECT * FROM carrito WHERE usuario_id = ?', [usuarioId]);
  }

  Future<void> limpiarCarrito(int usuarioId) async {
    final db = await instance.database;
    await db.rawDelete('DELETE FROM carrito WHERE usuario_id = ?', [usuarioId]);
  }

  Future<void> eliminarDelCarrito(int id) async {
    final db = await instance.database;
    await db.rawDelete('DELETE FROM carrito WHERE id = ?', [id]);
  }

  // ─── HISTORIAL ─────────────────────────────────────────────────────────────

  Future<void> guardarCompra(int usuarioId, String productosJson, double total, String transactionId,
      {String? metodoPago, String? detallePago, String estadoPago = 'aprobado'}) async {
    final db = await instance.database;
    await db.insert('historial_compras', {
      'metodo_pago': metodoPago,
      'detalle_pago': detallePago,
      'estado_pago': estadoPago,
      'usuario_id': usuarioId,
      'productos_json': productosJson,
      'total': total,
      'fecha': DateTime.now().toIso8601String(),
      'transaction_id': transactionId,
    });
  }

  Future<List<Map<String, dynamic>>> obtenerHistorial(int usuarioId) async {
    final db = await instance.database;
    return await db.rawQuery(
      'SELECT * FROM historial_compras WHERE usuario_id = ? ORDER BY fecha DESC',
      [usuarioId],
    );
  }

  Future<List<Map<String, dynamic>>> obtenerTodoHistorial() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT h.*, u.nombre as usuario_nombre, u.email as usuario_email
      FROM historial_compras h
      JOIN usuarios u ON h.usuario_id = u.id
      ORDER BY h.fecha DESC
    ''');
  }

  // ─── NOTIFICACIONES ────────────────────────────────────────────────────────

  Future<int> insertarNotificacion(int usuarioId, String titulo, String cuerpo, String tipo) async {
    final db = await instance.database;
    return await db.insert('notificaciones', {
      'usuario_id': usuarioId,
      'titulo': titulo,
      'cuerpo': cuerpo,
      'tipo': tipo,
      'leida': 0,
      'fecha': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> obtenerNotificaciones(int usuarioId) async {
    final db = await instance.database;
    return await db.query('notificaciones',
        where: 'usuario_id = ?', whereArgs: [usuarioId], orderBy: 'fecha DESC', limit: 100);
  }

  Future<int> contarNoLeidas(int usuarioId) async {
    final db = await instance.database;
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM notificaciones WHERE usuario_id = ? AND leida = 0', [usuarioId]);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> marcarNotificacionesLeidas(int usuarioId) async {
    final db = await instance.database;
    await db.update('notificaciones', {'leida': 1}, where: 'usuario_id = ?', whereArgs: [usuarioId]);
  }

  Future<void> eliminarNotificaciones(int usuarioId) async {
    final db = await instance.database;
    await db.delete('notificaciones', where: 'usuario_id = ?', whereArgs: [usuarioId]);
  }

  // ─── INTERACCIONES (para recomendaciones) ─────────────────────────────────

  Future<void> registrarInteraccion(int usuarioId, int productoId, String tipo) async {
    final db = await instance.database;
    await db.insert('interacciones', {
      'usuario_id': usuarioId,
      'producto_id': productoId,
      'tipo': tipo,
      'fecha': DateTime.now().toIso8601String(),
    });
  }

  /// Puntaje por categoría: vista = 1, carrito = 3, compra = 5.
  Future<Map<String, double>> puntajesPorCategoria(int usuarioId) async {
    final db = await instance.database;
    final r = await db.rawQuery('''
      SELECT p.categoria AS categoria,
             SUM(CASE i.tipo WHEN 'compra' THEN 5 WHEN 'carrito' THEN 3 ELSE 1 END) AS puntaje
      FROM interacciones i
      JOIN productos p ON p.id = i.producto_id
      WHERE i.usuario_id = ?
      GROUP BY p.categoria
    ''', [usuarioId]);
    return {
      for (final f in r)
        (f['categoria'] as String? ?? 'General'): (f['puntaje'] as num).toDouble(),
    };
  }

  Future<Set<int>> productosComprados(int usuarioId) async {
    final db = await instance.database;
    final r = await db.rawQuery(
        "SELECT DISTINCT producto_id FROM interacciones WHERE usuario_id = ? AND tipo = 'compra'",
        [usuarioId]);
    return r.map((e) => e['producto_id'] as int).toSet();
  }

  Future<void> cerrar() async {
    final db = await instance.database;
    await db.close();
  }
}
