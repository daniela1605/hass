import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';
import '../models/usuario.dart';
import '../repository/database_helper.dart';
import 'app_settings.dart';
import 'mail_helper.dart';
import 'notification_service.dart';
import 'otp_service.dart';
import 'security_service.dart';
import 'sms_helper.dart';

/// Usuario con la sesión activa.
class Sesion {
  Sesion._();
  static final Sesion instance = Sesion._();

  Usuario? usuario;
  String metodo = 'password'; // password | google | biometria

  bool get activa => usuario != null;
  bool get esAdmin => usuario?.rol == 'admin';
  bool get puedeEditarProductos => usuario?.rol == 'admin' || usuario?.rol == 'editor';
}

class ResultadoLogin {
  final Usuario? usuario;
  final String? error;
  const ResultadoLogin.ok(this.usuario) : error = null;
  const ResultadoLogin.error(this.error) : usuario = null;
  bool get ok => usuario != null;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final DatabaseHelper _db = DatabaseHelper.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final GoogleSignIn _google = GoogleSignIn(scopes: ['email', 'profile']);

  /// Usuarios que ya verificaron su código de recuperación (id → vencimiento).
  final Map<int, DateTime> _resetAutorizado = {};

  // ─── LOGIN CON CONTRASEÑA (paso 1 de 2) ────────────────────────────────────

  Future<ResultadoLogin> validarCredenciales(String identificador, String password) async {
    const generico = 'Usuario/correo o contraseña incorrectos.';
    final usuario = await _db.obtenerPorIdentificador(identificador);
    if (usuario == null || usuario.id == null) {
      return const ResultadoLogin.error(generico);
    }

    if (usuario.estaBloqueado) {
      final min = usuario.bloqueadoHasta!.difference(DateTime.now()).inMinutes + 1;
      return ResultadoLogin.error(
          'Cuenta bloqueada temporalmente por intentos fallidos. Intenta en $min min o restablece tu contraseña.');
    }

    final ok = await SecurityService.verificarPassword(password, usuario.password);
    if (!ok) {
      final politica = PoliticaRol.de(usuario.rol);
      final intentos = usuario.intentosFallidos + 1;
      if (intentos >= politica.maxIntentos) {
        final hasta = DateTime.now().add(politica.bloqueo);
        await _db.registrarIntentoFallido(usuario.id!, 0, hasta);
        MailHelper.sendSecurityAlertEmail(
          usuario.email,
          'Cuenta bloqueada temporalmente',
          'Detectamos $intentos intentos fallidos de inicio de sesión en tu cuenta. '
              'Se bloqueó por ${politica.bloqueo.inMinutes} minutos.',
        );
        NotificationService.instance.notificar(
          usuario.id!,
          'Cuenta bloqueada',
          'Se bloqueó tu cuenta ${politica.bloqueo.inMinutes} min por intentos fallidos.',
          tipo: 'seguridad',
        );
        return ResultadoLogin.error(
            'Demasiados intentos. Cuenta bloqueada ${politica.bloqueo.inMinutes} minutos.');
      }
      await _db.registrarIntentoFallido(usuario.id!, intentos, null);
      final restantes = politica.maxIntentos - intentos;
      return ResultadoLogin.error('$generico Te quedan $restantes intento(s).');
    }

    await _db.reiniciarIntentos(usuario.id!);
    // Migración silenciosa de contraseñas antiguas en texto plano.
    if (!SecurityService.esHash(usuario.password)) {
      await _db.actualizarPasswordHash(usuario.id!, await SecurityService.hashPassword(password));
    }
    return ResultadoLogin.ok(usuario);
  }

  // ─── 2FA (paso 2 de 2) ─────────────────────────────────────────────────────

  Future<EnvioCodigo> enviarOtpLogin(Usuario u, CanalOtp canal) {
    return OtpService.instance.enviar(
      proposito: 'login',
      sujeto: '${u.id}',
      nombre: u.nombre,
      email: u.email,
      telefono: u.telefono,
      canal: canal,
      vigencia: PoliticaRol.de(u.rol).vigenciaOtp,
      emailOculto: u.emailOculto,
      telefonoOculto: u.telefonoOculto,
    );
  }

  ResultadoVerificacion verificarOtpLogin(Usuario u, String codigo) =>
      OtpService.instance.verificar('login', '${u.id}', codigo);

  /// Abre la sesión (después de 2FA, Google o biometría).
  Future<void> iniciarSesion(Usuario u, {String metodo = 'password'}) async {
    Sesion.instance.usuario = u;
    Sesion.instance.metodo = metodo;
    final textoMetodo = {
      'password': 'contraseña + código 2FA',
      'google': 'Google',
      'biometria': 'biometría',
    }[metodo];
    await NotificationService.instance.notificar(
      u.id!,
      'Nuevo inicio de sesión',
      'Entraste con $textoMetodo el ${_fecha(DateTime.now())}.',
      tipo: 'seguridad',
    );
  }

  Future<void> cerrarSesion() async {
    if (Sesion.instance.metodo == 'google') {
      try {
        await _google.signOut();
      } catch (_) {}
    }
    Sesion.instance.usuario = null;
    NotificationService.instance.noLeidas.value = 0;
  }

  /// Recarga los datos del usuario en sesión desde la BD.
  Future<void> refrescarSesion() async {
    final id = Sesion.instance.usuario?.id;
    if (id == null) return;
    final u = await _db.obtenerPorId(id);
    if (u != null) Sesion.instance.usuario = u;
  }

  // ─── RECUPERACIÓN DE USUARIO ───────────────────────────────────────────────

  /// Envía el nombre de usuario al correo (y por SMS si se buscó por teléfono).
  /// Siempre responde igual para no revelar qué cuentas existen.
  Future<String> recuperarUsuario(String dato) async {
    final d = dato.trim();
    Usuario? u;
    var porTelefono = false;
    if (d.contains('@')) {
      u = await _db.obtenerPorEmail(d);
    } else {
      u = await _db.obtenerPorTelefono(d);
      porTelefono = true;
    }

    if (u != null) {
      final enviadoCorreo =
          await MailHelper.sendUsernameRecoveryEmail(u.email, u.nombre, u.username, u.etiquetaRol);
      var enviadoSms = false;
      if (porTelefono) {
        enviadoSms = await SmsHelper.enviar(u.telefono,
            'Tu usuario es: ${u.username} (cuenta ${u.etiquetaRol}). Correo: ${u.emailOculto}');
      }
      if (!enviadoCorreo && !enviadoSms) {
        // Modo demo: se simula el mensaje con una notificación del sistema.
        await NotificationService.instance.mostrarSistema(
          porTelefono ? '💬 SMS (demo) · Recuperación de usuario' : '📧 Correo (demo) · Recuperación de usuario',
          'Tu usuario es "${u.username}" · Cuenta ${u.etiquetaRol} · ${u.emailOculto}',
          tipo: 'seguridad',
        );
      }
      await NotificationService.instance.notificar(
        u.id!,
        'Recuperación de usuario',
        'Se solicitó recordar tu nombre de usuario.',
        tipo: 'seguridad',
      );
    }
    return porTelefono
        ? 'Si el teléfono está registrado, enviamos tu nombre de usuario por SMS y a tu correo.'
        : 'Si el correo está registrado, te enviamos tu nombre de usuario.';
  }

  // ─── RECUPERACIÓN DE CONTRASEÑA ────────────────────────────────────────────

  Future<Usuario?> buscarCuenta(String identificador) => _db.obtenerPorIdentificador(identificador);

  Future<EnvioCodigo?> solicitarCodigoReset(String identificador, CanalOtp canal) async {
    final u = await _db.obtenerPorIdentificador(identificador);
    if (u == null || u.id == null) return null;
    return OtpService.instance.enviar(
      proposito: 'reset',
      sujeto: '${u.id}',
      nombre: u.nombre,
      email: u.email,
      telefono: u.telefono,
      canal: canal,
      vigencia: PoliticaRol.de(u.rol).vigenciaRecuperacion,
      emailOculto: u.emailOculto,
      telefonoOculto: u.telefonoOculto,
    );
  }

  Future<ResultadoVerificacion> verificarCodigoReset(String identificador, String codigo) async {
    final u = await _db.obtenerPorIdentificador(identificador);
    if (u == null || u.id == null) {
      return const ResultadoVerificacion(EstadoVerificacion.inexistente);
    }
    final r = OtpService.instance.verificar('reset', '${u.id}', codigo);
    if (r.ok) {
      _resetAutorizado[u.id!] = DateTime.now().add(const Duration(minutes: 10));
    }
    return r;
  }

  /// Guarda la nueva contraseña. Devuelve `null` si todo salió bien o el error.
  Future<String?> restablecerPassword(String identificador, String nueva) async {
    final u = await _db.obtenerPorIdentificador(identificador);
    if (u == null || u.id == null) return 'Cuenta no encontrada.';
    final permiso = _resetAutorizado[u.id!];
    if (permiso == null || DateTime.now().isAfter(permiso)) {
      return 'La verificación expiró. Solicita un código nuevo.';
    }
    final error = await _guardarNuevaPassword(u, nueva);
    if (error == null) _resetAutorizado.remove(u.id!);
    return error;
  }

  /// Cambio de contraseña desde Ajustes (requiere la actual).
  Future<String?> cambiarPassword(Usuario u, String actual, String nueva) async {
    final fresco = await _db.obtenerPorId(u.id!);
    if (fresco == null) return 'Cuenta no encontrada.';
    if (fresco.proveedor != 'google' || actual.isNotEmpty) {
      if (!await SecurityService.verificarPassword(actual, fresco.password)) {
        return 'La contraseña actual no es correcta.';
      }
    }
    return _guardarNuevaPassword(fresco, nueva);
  }

  Future<String?> _guardarNuevaPassword(Usuario u, String nueva) async {
    final error = PoliticaRol.de(u.rol).validarPassword(nueva);
    if (error != null) return error;
    if (await SecurityService.verificarPassword(nueva, u.password)) {
      return 'La nueva contraseña debe ser diferente a la anterior.';
    }
    await _db.actualizarPasswordHash(u.id!, await SecurityService.hashPassword(nueva));
    MailHelper.sendSecurityAlertEmail(
      u.email,
      'Tu contraseña fue cambiada',
      'Hola ${u.nombre}, la contraseña de tu cuenta ${u.etiquetaRol} se cambió correctamente.',
    );
    await NotificationService.instance.notificar(
      u.id!,
      'Contraseña actualizada',
      'Tu contraseña se cambió el ${_fecha(DateTime.now())}.',
      tipo: 'seguridad',
    );
    return null;
  }

  // ─── INICIO DE SESIÓN CON GOOGLE ───────────────────────────────────────────

  Future<ResultadoLogin> loginConGoogle() async {
    try {
      final cuenta = await _google.signIn();
      if (cuenta == null) return const ResultadoLogin.error('Inicio con Google cancelado.');

      var u = await _db.obtenerPorEmail(cuenta.email);
      if (u == null) {
        final (nombres, paterno, materno) =
            Usuario.separarNombre(cuenta.displayName ?? cuenta.email.split('@').first);
        final nuevo = Usuario.conNombre(
          nombres: nombres,
          apellidoPaterno: paterno,
          apellidoMaterno: materno,
          email: cuenta.email,
          username: await generarUsername(cuenta.email),
          password: await SecurityService.hashPassword(SecurityService.passwordAleatoria()),
          rol: 'lector', // las cuentas sociales siempre entran con el rol mínimo
          proveedor: 'google',
        );
        final id = await _db.insertar(nuevo);
        u = await _db.obtenerPorId(id);
      }
      if (u!.estaBloqueado) {
        return const ResultadoLogin.error('La cuenta está bloqueada temporalmente.');
      }
      return ResultadoLogin.ok(u);
    } on PlatformException catch (e) {
      debugPrint('Google Sign-In: ${e.code} ${e.message}');
      final msg = (e.code == 'sign_in_failed' || '${e.message}'.contains('10'))
          ? 'Google Sign-In no está configurado para esta app (falta registrar el SHA-1 en Google Cloud).'
          : 'No se pudo iniciar con Google: ${e.message ?? e.code}';
      return ResultadoLogin.error(msg);
    } catch (e) {
      return ResultadoLogin.error('No se pudo iniciar con Google: $e');
    }
  }

  // ─── BIOMETRÍA ─────────────────────────────────────────────────────────────

  Future<bool> biometriaDisponible() async {
    try {
      return await _localAuth.isDeviceSupported() &&
          (await _localAuth.canCheckBiometrics ||
              (await _localAuth.getAvailableBiometrics()).isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// Huella, rostro o, si no hay, el PIN/patrón del dispositivo.
  Future<bool> autenticarBiometria(String motivo) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: motivo,
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
    } on PlatformException catch (e) {
      debugPrint('Biometría: ${e.code} ${e.message}');
      return false;
    }
  }

  Future<ResultadoLogin> loginBiometrico() async {
    final id = AppSettings.instance.biometriaUsuarioId;
    if (id == null) return const ResultadoLogin.error('La biometría no está activada.');
    final ok = await autenticarBiometria('Confirma tu identidad para entrar');
    if (!ok) return const ResultadoLogin.error('No se pudo verificar tu identidad.');
    final u = await _db.obtenerPorId(id);
    if (u == null) {
      await AppSettings.instance.setBiometriaUsuario(null);
      return const ResultadoLogin.error('La cuenta vinculada ya no existe.');
    }
    if (u.estaBloqueado) return const ResultadoLogin.error('La cuenta está bloqueada temporalmente.');
    return ResultadoLogin.ok(u);
  }

  // ─── Utilidades ────────────────────────────────────────────────────────────

  Future<String> generarUsername(String email) async {
    var base = email.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]'), '');
    if (base.length < 3) base = 'usuario$base';
    var candidato = base;
    var n = 1;
    while (await _db.existeUsername(candidato)) {
      candidato = '$base${n++}';
    }
    return candidato;
  }

  static String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
