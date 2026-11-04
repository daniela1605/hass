import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reglas de seguridad según el rol. Cuanto más privilegios, más estrictas.
class PoliticaRol {
  final String rol;
  final int minLongitud;
  final bool requiereMayuscula;
  final bool requiereNumero;
  final bool requiereSimbolo;
  final int maxIntentos; // intentos fallidos antes de bloquear
  final Duration bloqueo; // tiempo de bloqueo tras exceder intentos
  final Duration vigenciaOtp; // vigencia del código 2FA
  final Duration vigenciaRecuperacion; // vigencia del código de recuperación

  const PoliticaRol({
    required this.rol,
    required this.minLongitud,
    required this.requiereMayuscula,
    required this.requiereNumero,
    required this.requiereSimbolo,
    required this.maxIntentos,
    required this.bloqueo,
    required this.vigenciaOtp,
    required this.vigenciaRecuperacion,
  });

  static const admin = PoliticaRol(
    rol: 'admin',
    minLongitud: 10,
    requiereMayuscula: true,
    requiereNumero: true,
    requiereSimbolo: true,
    maxIntentos: 3,
    bloqueo: Duration(minutes: 15),
    vigenciaOtp: Duration(minutes: 3),
    vigenciaRecuperacion: Duration(minutes: 5),
  );

  static const editor = PoliticaRol(
    rol: 'editor',
    minLongitud: 8,
    requiereMayuscula: true,
    requiereNumero: true,
    requiereSimbolo: false,
    maxIntentos: 5,
    bloqueo: Duration(minutes: 10),
    vigenciaOtp: Duration(minutes: 5),
    vigenciaRecuperacion: Duration(minutes: 10),
  );

  static const lector = PoliticaRol(
    rol: 'lector',
    minLongitud: 8,
    requiereMayuscula: false,
    requiereNumero: true,
    requiereSimbolo: false,
    maxIntentos: 5,
    bloqueo: Duration(minutes: 5),
    vigenciaOtp: Duration(minutes: 5),
    vigenciaRecuperacion: Duration(minutes: 15),
  );

  static PoliticaRol de(String rol) {
    switch (rol) {
      case 'admin':
        return admin;
      case 'editor':
        return editor;
      default:
        return lector;
    }
  }

  /// Lista legible de requisitos de contraseña.
  List<String> get requisitos => [
        'Mínimo $minLongitud caracteres',
        'Al menos una letra',
        if (requiereMayuscula) 'Al menos una mayúscula',
        if (requiereNumero) 'Al menos un número',
        if (requiereSimbolo) 'Al menos un símbolo (!@#\$%...)',
      ];

  /// Devuelve `null` si la contraseña cumple, o el mensaje de error.
  String? validarPassword(String pass) {
    if (pass.length < minLongitud) {
      return 'La contraseña debe tener al menos $minLongitud caracteres.';
    }
    if (!RegExp(r'[A-Za-zÁÉÍÓÚáéíóúÑñ]').hasMatch(pass)) {
      return 'La contraseña debe incluir al menos una letra.';
    }
    if (requiereMayuscula && !RegExp(r'[A-ZÁÉÍÓÚÑ]').hasMatch(pass)) {
      return 'Para el rol "$rol" la contraseña necesita una mayúscula.';
    }
    if (requiereNumero && !RegExp(r'\d').hasMatch(pass)) {
      return 'La contraseña debe incluir al menos un número.';
    }
    if (requiereSimbolo && !RegExp(r'[^A-Za-z0-9ÁÉÍÓÚáéíóúÑñ]').hasMatch(pass)) {
      return 'Para el rol "$rol" la contraseña necesita un símbolo.';
    }
    return null;
  }
}

/// Hash de contraseñas (PBKDF2-HMAC-SHA256), cifrado AES-GCM de datos
/// personales y generación de códigos aleatorios seguros.
class SecurityService {
  SecurityService._();

  static const int _iteraciones = 12000;
  static const String _prefijoHash = 'pbkdf2';
  static const String _prefijoCifrado = 'enc:v1:';
  static const String _claveAes = 'app_aes_key_v1';

  static final Random _random = Random.secure();
  static enc.Key? _key;

  // ─── Inicialización (clave AES en almacenamiento seguro del sistema) ─────
  static Future<void> init() async {
    if (_key != null) return;
    String? b64;
    const storage = FlutterSecureStorage();
    try {
      b64 = await storage.read(key: _claveAes);
      if (b64 == null) {
        b64 = base64Encode(_bytesAleatorios(32));
        await storage.write(key: _claveAes, value: b64);
      }
    } catch (e) {
      // Respaldo si el Keystore del dispositivo falla.
      debugPrint('SecureStorage no disponible, usando respaldo: $e');
      final prefs = await SharedPreferences.getInstance();
      b64 = prefs.getString(_claveAes);
      if (b64 == null) {
        b64 = base64Encode(_bytesAleatorios(32));
        await prefs.setString(_claveAes, b64);
      }
    }
    _key = enc.Key(base64Decode(b64));
  }

  // ─── Contraseñas ──────────────────────────────────────────────────────────
  static bool esHash(String valor) => valor.startsWith('$_prefijoHash\$');

  /// Genera el hash con sal aleatoria. Se ejecuta en un isolate para no
  /// congelar la interfaz.
  static Future<String> hashPassword(String password) async {
    final salt = _bytesAleatorios(16);
    final hash = await compute(_pbkdf2Isolate, [password, salt, _iteraciones]);
    return '$_prefijoHash\$$_iteraciones\$${base64Encode(salt)}\$${base64Encode(hash)}';
  }

  /// Verifica una contraseña contra el valor guardado.
  /// Acepta contraseñas antiguas en texto plano (para migración).
  static Future<bool> verificarPassword(String password, String guardado) async {
    if (!esHash(guardado)) {
      return _igualesTiempoConstante(utf8.encode(password), utf8.encode(guardado));
    }
    final partes = guardado.split('\$');
    if (partes.length != 4) return false;
    final iter = int.tryParse(partes[1]) ?? _iteraciones;
    final salt = base64Decode(partes[2]);
    final esperado = base64Decode(partes[3]);
    final calculado = await compute(_pbkdf2Isolate, [password, salt, iter]);
    return _igualesTiempoConstante(calculado, esperado);
  }

  // ─── Cifrado de datos personales ──────────────────────────────────────────
  static String cifrar(String? texto) {
    if (texto == null || texto.isEmpty) return '';
    if (texto.startsWith(_prefijoCifrado)) return texto;
    final key = _key;
    if (key == null) return texto;
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final cifrado = encrypter.encrypt(texto, iv: iv);
    return '$_prefijoCifrado${iv.base64}:${cifrado.base64}';
  }

  static String descifrar(String? valor) {
    if (valor == null || valor.isEmpty) return '';
    if (!valor.startsWith(_prefijoCifrado)) return valor;
    final key = _key;
    if (key == null) return '';
    try {
      final partes = valor.substring(_prefijoCifrado.length).split(':');
      final iv = enc.IV.fromBase64(partes[0]);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      return encrypter.decrypt64(partes[1], iv: iv);
    } catch (_) {
      return '';
    }
  }

  // ─── Códigos ──────────────────────────────────────────────────────────────
  static String generarCodigo([int digitos = 6]) {
    final b = StringBuffer();
    for (var i = 0; i < digitos; i++) {
      b.write(_random.nextInt(10));
    }
    return b.toString();
  }

  static String hashCodigo(String codigo) =>
      sha256.convert(utf8.encode('otp:$codigo')).toString();

  static bool compararCodigo(String codigo, String hashGuardado) =>
      _igualesTiempoConstante(
        utf8.encode(hashCodigo(codigo.trim())),
        utf8.encode(hashGuardado),
      );

  static String passwordAleatoria() =>
      base64UrlEncode(_bytesAleatorios(24));

  // ─── Utilidades internas ──────────────────────────────────────────────────
  static Uint8List _bytesAleatorios(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  static bool _igualesTiempoConstante(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a[i] ^ b[i];
    }
    return r == 0;
  }
}

/// PBKDF2-HMAC-SHA256 (se ejecuta en otro isolate vía `compute`).
List<int> _pbkdf2Isolate(List<Object> args) {
  final password = args[0] as String;
  final salt = args[1] as List<int>;
  final iteraciones = args[2] as int;
  const longitud = 32;

  final hmac = Hmac(sha256, utf8.encode(password));
  final bloque = <int>[...salt, 0, 0, 0, 1];
  var u = hmac.convert(bloque).bytes;
  final t = List<int>.from(u);
  for (var i = 1; i < iteraciones; i++) {
    u = hmac.convert(u).bytes;
    for (var k = 0; k < t.length; k++) {
      t[k] ^= u[k];
    }
  }
  return t.sublist(0, longitud);
}
