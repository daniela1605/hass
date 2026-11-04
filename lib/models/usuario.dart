import '../services/security_service.dart';

class Usuario {
  final int? id;

  /// Nombre completo (nombres + apellido paterno + apellido materno).
  final String nombre;
  final String nombres;
  final String apellidoPaterno;
  final String apellidoMaterno;
  final String email;
  final String username;

  /// Hash PBKDF2 de la contraseña (nunca texto plano).
  final String password;
  final String rol;

  /// Teléfono en claro (en la BD se guarda cifrado con AES-GCM).
  final String telefono;

  /// 'local' o 'google'.
  final String proveedor;
  final int intentosFallidos;
  final DateTime? bloqueadoHasta;

  Usuario({
    this.id,
    required this.nombre,
    this.nombres = '',
    this.apellidoPaterno = '',
    this.apellidoMaterno = '',
    required this.email,
    this.username = '',
    required this.password,
    required this.rol,
    this.telefono = '',
    this.proveedor = 'local',
    this.intentosFallidos = 0,
    this.bloqueadoHasta,
  });

  /// Crea el usuario a partir de las partes del nombre.
  factory Usuario.conNombre({
    int? id,
    required String nombres,
    required String apellidoPaterno,
    String apellidoMaterno = '',
    required String email,
    String username = '',
    required String password,
    required String rol,
    String telefono = '',
    String proveedor = 'local',
  }) {
    return Usuario(
      id: id,
      nombre: componerNombre(nombres, apellidoPaterno, apellidoMaterno),
      nombres: nombres.trim(),
      apellidoPaterno: apellidoPaterno.trim(),
      apellidoMaterno: apellidoMaterno.trim(),
      email: email,
      username: username,
      password: password,
      rol: rol,
      telefono: telefono,
      proveedor: proveedor,
    );
  }

  /// "Juan Carlos" + "Pérez" + "Gómez" → "Juan Carlos Pérez Gómez"
  static String componerNombre(String nombres, String paterno, String materno) =>
      [nombres, paterno, materno].map((e) => e.trim()).where((e) => e.isNotEmpty).join(' ');

  /// Separa un nombre completo antiguo: las 2 últimas palabras son los
  /// apellidos y el resto los nombres (ej. "Juan Carlos Pérez Gómez").
  static (String, String, String) separarNombre(String completo) {
    final p = completo.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (p.isEmpty) return ('', '', '');
    if (p.length == 1) return (p[0], '', '');
    if (p.length == 2) return (p[0], p[1], '');
    return (p.sublist(0, p.length - 2).join(' '), p[p.length - 2], p[p.length - 1]);
  }

  /// Nombre corto para saludos: primer nombre + apellido paterno.
  String get nombreCorto {
    final primero = (nombres.isNotEmpty ? nombres : nombre).split(' ').first;
    return apellidoPaterno.isEmpty ? primero : '$primero $apellidoPaterno';
  }

  bool get estaBloqueado =>
      bloqueadoHasta != null && bloqueadoHasta!.isAfter(DateTime.now());

  bool get tieneTelefono => telefono.trim().isNotEmpty;

  String get etiquetaRol {
    switch (rol) {
      case 'admin':
        return 'Administrador';
      case 'editor':
        return 'Editor';
      default:
        return 'Comprador';
    }
  }

  /// Teléfono enmascarado para mostrar: ******1234
  String get telefonoOculto {
    final t = telefono.replaceAll(RegExp(r'\D'), '');
    if (t.length <= 4) return t;
    return '${'•' * (t.length - 4)}${t.substring(t.length - 4)}';
  }

  /// Correo enmascarado para mostrar: ju***@gmail.com
  String get emailOculto {
    final partes = email.split('@');
    if (partes.length != 2) return email;
    final u = partes[0];
    final visible = u.length <= 2 ? u.substring(0, 1) : u.substring(0, 2);
    return '$visible***@${partes[1]}';
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nombre': nombre.trim(),
      'nombres': nombres.trim(),
      'apellido_paterno': apellidoPaterno.trim(),
      'apellido_materno': apellidoMaterno.trim(),
      'email': email.trim().toLowerCase(),
      'username': username.trim().toLowerCase(),
      'password': password,
      'rol': rol,
      'telefono': SecurityService.cifrar(telefono.trim()),
      'proveedor': proveedor,
      'intentos_fallidos': intentosFallidos,
      'bloqueado_hasta': bloqueadoHasta?.toIso8601String(),
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory Usuario.fromMap(Map<String, dynamic> map) {
    final completo = map['nombre'] as String? ?? '';
    var nombres = map['nombres'] as String? ?? '';
    var paterno = map['apellido_paterno'] as String? ?? '';
    var materno = map['apellido_materno'] as String? ?? '';
    if (nombres.isEmpty && completo.isNotEmpty) {
      (nombres, paterno, materno) = separarNombre(completo);
    }
    return Usuario(
      id: map['id'] as int?,
      nombre: completo,
      nombres: nombres,
      apellidoPaterno: paterno,
      apellidoMaterno: materno,
      email: map['email'] as String? ?? '',
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      rol: map['rol'] as String? ?? 'lector',
      telefono: SecurityService.descifrar(map['telefono'] as String?),
      proveedor: map['proveedor'] as String? ?? 'local',
      intentosFallidos: (map['intentos_fallidos'] as int?) ?? 0,
      bloqueadoHasta: DateTime.tryParse(map['bloqueado_hasta'] as String? ?? ''),
    );
  }

  Usuario copyWith({
    int? id,
    String? nombre,
    String? email,
    String? username,
    String? password,
    String? rol,
    String? telefono,
    String? proveedor,
  }) {
    return Usuario(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      nombres: nombres,
      apellidoPaterno: apellidoPaterno,
      apellidoMaterno: apellidoMaterno,
      email: email ?? this.email,
      username: username ?? this.username,
      password: password ?? this.password,
      rol: rol ?? this.rol,
      telefono: telefono ?? this.telefono,
      proveedor: proveedor ?? this.proveedor,
      intentosFallidos: intentosFallidos,
      bloqueadoHasta: bloqueadoHasta,
    );
  }
}
