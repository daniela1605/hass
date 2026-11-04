import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import 'mail_helper.dart';
import 'notification_service.dart';
import 'security_service.dart';
import 'sms_helper.dart';

enum CanalOtp { email, sms }

/// Resultado del envío de un código.
class EnvioCodigo {
  final bool enviado; // true si salió por correo/SMS real
  final CanalOtp canal;
  final String destinoOculto; // ju***@gmail.com / ••••••1234
  final DateTime vence;

  /// Solo en modo demo (sin credenciales): el código para mostrarlo en pantalla.
  final String? codigoDemo;

  EnvioCodigo({
    required this.enviado,
    required this.canal,
    required this.destinoOculto,
    required this.vence,
    this.codigoDemo,
  });
}

enum EstadoVerificacion { correcto, incorrecto, expirado, agotado, inexistente }

class ResultadoVerificacion {
  final EstadoVerificacion estado;
  final int intentosRestantes;
  const ResultadoVerificacion(this.estado, [this.intentosRestantes = 0]);

  bool get ok => estado == EstadoVerificacion.correcto;

  String get mensaje {
    switch (estado) {
      case EstadoVerificacion.correcto:
        return 'Código verificado.';
      case EstadoVerificacion.incorrecto:
        return 'Código incorrecto. Te quedan $intentosRestantes intento(s).';
      case EstadoVerificacion.expirado:
        return 'El código expiró. Solicita uno nuevo.';
      case EstadoVerificacion.agotado:
        return 'Demasiados intentos. Solicita un código nuevo.';
      case EstadoVerificacion.inexistente:
        return 'No hay un código activo. Solicita uno nuevo.';
    }
  }
}

class _CodigoActivo {
  final String hash;
  final DateTime vence;
  final DateTime enviado;
  int intentos = 0;
  _CodigoActivo(this.hash, this.vence, this.enviado);
}

/// Códigos de un solo uso (OTP) para 2FA, recuperación y registro.
///  * Se guardan solo como hash SHA-256 en memoria.
///  * Expiran y tienen un máximo de intentos.
///  * Se envían por correo o SMS; en modo demo se muestran en pantalla.
class OtpService {
  OtpService._();
  static final OtpService instance = OtpService._();

  static const int maxIntentos = 3;
  static const Duration esperaReenvio = Duration(seconds: 30);

  final Map<String, _CodigoActivo> _codigos = {};

  String _clave(String proposito, String sujeto) => '$proposito:$sujeto';

  /// Segundos que faltan para poder reenviar (0 = ya se puede).
  int segundosParaReenviar(String proposito, String sujeto) {
    final c = _codigos[_clave(proposito, sujeto)];
    if (c == null) return 0;
    final restante = esperaReenvio - DateTime.now().difference(c.enviado);
    return restante.isNegative ? 0 : restante.inSeconds;
  }

  Future<EnvioCodigo> enviar({
    required String proposito, // 'login' | 'reset' | 'registro'
    required String sujeto, // id de usuario o correo
    required String nombre,
    required String email,
    String telefono = '',
    CanalOtp canal = CanalOtp.email,
    Duration vigencia = const Duration(minutes: 5),
    String emailOculto = '',
    String telefonoOculto = '',
  }) async {
    if (canal == CanalOtp.sms && telefono.trim().isEmpty) canal = CanalOtp.email;

    final codigo = SecurityService.generarCodigo(6);
    final ahora = DateTime.now();
    final vence = ahora.add(vigencia);
    _codigos[_clave(proposito, sujeto)] =
        _CodigoActivo(SecurityService.hashCodigo(codigo), vence, ahora);

    final minutos = vigencia.inMinutes;
    bool enviado;
    if (canal == CanalOtp.sms) {
      enviado = await SmsHelper.enviar(
        telefono,
        '${AppConfig.appName}: tu código es $codigo. Vence en $minutos min. No lo compartas.',
      );
      if (!enviado) {
        // Modo demo: simulamos la llegada del SMS con una notificación local.
        await NotificationService.instance.mostrarSistema(
          '💬 SMS (demo) · ${AppConfig.appName}',
          'Tu código de verificación es $codigo. Vence en $minutos min.',
          tipo: 'seguridad',
        );
      }
    } else {
      switch (proposito) {
        case 'reset':
          enviado = await MailHelper.sendPasswordResetCodeEmail(email, nombre, codigo, minutos);
          break;
        case 'registro':
          enviado = await MailHelper.sendRegistroTokenEmail(email, codigo, nombre);
          break;
        default:
          enviado = await MailHelper.sendOTPEmail(email, codigo, minutos: minutos);
      }
    }

    if (!enviado) debugPrint('[DEMO] Código $proposito para $sujeto: $codigo');

    return EnvioCodigo(
      enviado: enviado,
      canal: canal,
      destinoOculto: canal == CanalOtp.sms ? telefonoOculto : (emailOculto.isEmpty ? email : emailOculto),
      vence: vence,
      codigoDemo: enviado ? null : codigo,
    );
  }

  ResultadoVerificacion verificar(String proposito, String sujeto, String codigo) {
    final clave = _clave(proposito, sujeto);
    final c = _codigos[clave];
    if (c == null) return const ResultadoVerificacion(EstadoVerificacion.inexistente);
    if (DateTime.now().isAfter(c.vence)) {
      _codigos.remove(clave);
      return const ResultadoVerificacion(EstadoVerificacion.expirado);
    }
    if (c.intentos >= maxIntentos) {
      _codigos.remove(clave);
      return const ResultadoVerificacion(EstadoVerificacion.agotado);
    }
    if (SecurityService.compararCodigo(codigo, c.hash)) {
      _codigos.remove(clave); // un solo uso
      return const ResultadoVerificacion(EstadoVerificacion.correcto);
    }
    c.intentos++;
    final restantes = maxIntentos - c.intentos;
    if (restantes <= 0) {
      _codigos.remove(clave);
      return const ResultadoVerificacion(EstadoVerificacion.agotado);
    }
    return ResultadoVerificacion(EstadoVerificacion.incorrecto, restantes);
  }

  void cancelar(String proposito, String sujeto) => _codigos.remove(_clave(proposito, sujeto));
}
