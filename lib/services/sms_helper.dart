import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Envío de SMS mediante la API REST de Twilio.
/// Si no hay credenciales en [AppConfig], devuelve `false` (modo demo).
class SmsHelper {
  static bool get configurado => AppConfig.smsConfigurado;

  /// Normaliza un teléfono a formato E.164 (+521234567890).
  static String normalizar(String telefono) {
    final t = telefono.trim();
    final digitos = t.replaceAll(RegExp(r'\D'), '');
    if (t.startsWith('+')) return '+$digitos';
    if (digitos.length == 10) return '${AppConfig.ladaPorDefecto}$digitos';
    return '+$digitos';
  }

  static Future<bool> enviar(String telefono, String mensaje) async {
    if (!configurado) {
      debugPrint('SMS no configurado (modo demo) → $telefono: $mensaje');
      return false;
    }
    try {
      final url = Uri.parse(
          'https://api.twilio.com/2010-04-01/Accounts/${AppConfig.twilioAccountSid}/Messages.json');
      final auth = base64Encode(
          utf8.encode('${AppConfig.twilioAccountSid}:${AppConfig.twilioAuthToken}'));
      final r = await http
          .post(
            url,
            headers: {'Authorization': 'Basic $auth'},
            body: {
              'To': normalizar(telefono),
              'From': AppConfig.twilioNumero,
              'Body': mensaje,
            },
          )
          .timeout(const Duration(seconds: 15));
      final ok = r.statusCode >= 200 && r.statusCode < 300;
      if (!ok) debugPrint('Twilio respondió ${r.statusCode}: ${r.body}');
      return ok;
    } catch (e) {
      debugPrint('Error enviando SMS: $e');
      return false;
    }
  }
}
