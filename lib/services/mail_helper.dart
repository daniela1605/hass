import 'package:flutter/foundation.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import '../config/app_config.dart';

class MailHelper {
  // ⚠️ Las credenciales se configuran en lib/config/app_config.dart
  static const String _username = AppConfig.smtpUsuario;
  static const String _password = AppConfig.smtpPassword;

  static SmtpServer get smtpServer => gmail(_username, _password);

  /// `true` si hay credenciales reales configuradas.
  static bool get configurado => AppConfig.correoConfigurado;

  /// Enviar correo genérico. Devuelve `true` si se envió.
  static Future<bool> sendEmail(
    String destino,
    String asunto,
    String mensaje, {
    String? htmlContent,
  }) async {
    final message = Message()
      ..from = Address(_username, AppConfig.smtpRemitente)
      ..recipients.add(destino)
      ..subject = asunto
      ..text = mensaje
      ..html = htmlContent ?? "<p style='font-family: Roboto;'>$mensaje</p>";

    if (!configurado) {
      debugPrint('Correo no configurado (modo demo). Destino: $destino · $asunto');
      return false;
    }
    try {
      await send(message, smtpServer).timeout(const Duration(seconds: 20));
      debugPrint('Correo enviado exitosamente a $destino');
      return true;
    } catch (e) {
      debugPrint('Error al enviar el correo: $e');
      // No relanzamos para evitar crash de UI en modo offline/pruebas
      return false;
    }
  }

  /// Plantilla HTML común.
  static String _plantilla(String titulo, String cuerpoHtml) => """
    <html>
      <body style="font-family: Roboto, sans-serif; color: #333; background: #FFF2F5; padding: 20px;">
        <div style="max-width: 560px; margin: auto; padding: 25px; border: 1px solid #F8BBD0; border-radius: 16px; background: white;">
          <h1 style="color: #EC407A; text-align: center;">$titulo</h1>
          $cuerpoHtml
          <footer style="text-align: center; font-size: 12px; color: #777; margin-top: 20px;">
            ${AppConfig.appName} · Este es un mensaje automático.
          </footer>
        </div>
      </body>
    </html>
  """;

  static String _bloqueCodigo(String codigo) => """
    <div style="background:#FFF2F5; border-radius:12px; padding:20px; margin:20px 0;">
      <h2 style="color:#EC407A; text-align:center; font-size:40px; letter-spacing:12px; margin:0;">$codigo</h2>
    </div>
  """;

  /// Código para restablecer contraseña.
  static Future<bool> sendPasswordResetCodeEmail(
      String destino, String nombre, String codigo, int minutos) {
    return sendEmail(
      destino,
      '🔑 Código para restablecer tu contraseña',
      'Hola $nombre, tu código para restablecer la contraseña es $codigo. Vence en $minutos minutos.',
      htmlContent: _plantilla('🔑 Restablecer contraseña', """
        <p>Hola <strong>$nombre</strong>, recibimos una solicitud para restablecer tu contraseña.</p>
        ${_bloqueCodigo(codigo)}
        <p style="text-align:center; color:#555;">El código vence en <strong>$minutos minutos</strong> y solo puede usarse una vez.</p>
        <p style="text-align:center; color:#999; font-size:13px;">Si no fuiste tú, ignora este correo: tu contraseña no cambiará.</p>
      """),
    );
  }

  /// Recordatorio del nombre de usuario.
  static Future<bool> sendUsernameRecoveryEmail(
      String destino, String nombre, String username, String rol) {
    return sendEmail(
      destino,
      '👤 Recuperación de nombre de usuario',
      'Hola $nombre, tu nombre de usuario es: $username',
      htmlContent: _plantilla('👤 Tu nombre de usuario', """
        <p>Hola <strong>$nombre</strong>, estos son los datos de acceso de tu cuenta:</p>
        <div style="background:#FFF2F5; border-radius:12px; padding:15px; margin:15px 0;">
          <p style="margin:4px 0;"><strong>Usuario:</strong> $username</p>
          <p style="margin:4px 0;"><strong>Correo:</strong> $destino</p>
          <p style="margin:4px 0;"><strong>Tipo de cuenta:</strong> $rol</p>
        </div>
        <p style="text-align:center; color:#555;">Puedes iniciar sesión con tu usuario o con tu correo.</p>
        <p style="text-align:center; color:#999; font-size:13px;">Si no solicitaste esta información, ignora este correo.</p>
      """),
    );
  }

  /// Alerta de seguridad (contraseña cambiada, cuenta bloqueada, etc.).
  static Future<bool> sendSecurityAlertEmail(
      String destino, String titulo, String mensaje) {
    return sendEmail(
      destino,
      '⚠️ $titulo',
      mensaje,
      htmlContent: _plantilla('⚠️ $titulo', """
        <p>$mensaje</p>
        <p style="color:#555;">Fecha: ${DateTime.now()}</p>
        <p style="color:#999; font-size:13px;">Si no reconoces esta actividad, restablece tu contraseña de inmediato.</p>
      """),
    );
  }

  /// Recuperación de contraseña
  static Future<bool> sendPasswordRecoveryEmail(
    String destino,
    String temporaryPassword,
  ) async {
    final asunto = 'Recuperación de Contraseña';
    final mensaje =
        'Tu nueva contraseña temporal es: $temporaryPassword. Por favor, cámbiala después de iniciar sesión.';
    final htmlContent = """
    <html>
      <body style="font-family: Roboto, sans-serif; color: #333; background: #FFF2F5; padding: 20px;">
        <div style="max-width: 600px; margin: auto; padding: 25px; border: 1px solid #F8BBD0; border-radius: 16px; background: white;">
          <h1 style="color: #EC407A; text-align: center;">🔑 Recuperación de Contraseña</h1>
          <p>Tu nueva contraseña temporal es:</p>
          <div style="background: #FFF2F5; border-radius: 12px; padding: 15px; margin: 15px 0;">
            <h2 style="color: #EC407A; text-align: center; font-size: 28px; margin: 0;">$temporaryPassword</h2>
          </div>
          <p style="text-align: center; color: #555;">Por favor, cámbiala inmediatamente después de iniciar sesión.</p>
          <footer style="text-align: center; font-size: 12px; color: #777; margin-top: 20px;">
            Si no solicitaste este cambio, ignora este correo.
          </footer>
        </div>
      </body>
    </html>
    """;

    return sendEmail(destino, asunto, mensaje, htmlContent: htmlContent);
  }

  /// Resumen de compra / Nota de Remisión
  static Future<bool> sendPurchaseSummaryEmail(
    String destino,
    List<Map<String, dynamic>> productos,
    double total,
    String transactionId,
    DateTime transactionDate, [
    Map<String, dynamic>? payerDetails,
    String? metodoPago,
  ]) async {
    final payerEmail = payerDetails?['email_address'] ?? destino;
    final countryCode = payerDetails?['address']?['country_code'] ?? 'MX';

    final asunto = '📋 Resumen de Compra - Nota de Remisión';
    final htmlContent = """
    <html>
      <body style="font-family: Roboto, sans-serif; color: #333; background: #FFF2F5; padding: 20px;">
        <div style="max-width: 600px; margin: auto; padding: 25px; border: 1px solid #F8BBD0; border-radius: 16px; background: white;">
          <h1 style="color: #EC407A; text-align: center;">🛍️ Resumen de Compra / Nota de Remisión</h1>
          <p style="text-align: center; color: #555;">¡Gracias por tu compra en Mi Tiendita! Aquí tienes los detalles:</p>

          <div style="background: #FFF2F5; border-radius: 12px; padding: 15px; margin: 15px 0;">
            <h3 style="color: #EC407A; margin-top: 0;">Detalles del Comprador</h3>
            <p style="margin: 4px 0;"><strong>Folio / Transacción:</strong> $transactionId</p>
            ${metodoPago == null ? '' : '<p style="margin: 4px 0;"><strong>Método de pago:</strong> $metodoPago</p>'}
            <p style="margin: 4px 0;"><strong>Fecha:</strong> ${transactionDate.day}/${transactionDate.month}/${transactionDate.year} ${transactionDate.hour}:${transactionDate.minute.toString().padLeft(2, '0')}</p>
            <p style="margin: 4px 0;"><strong>Correo Electrónico:</strong> $payerEmail</p>
            <p style="margin: 4px 0;"><strong>País:</strong> $countryCode</p>
          </div>

          <h3 style="color: #EC407A;">Productos Adquiridos</h3>
          <table border="1" cellpadding="10" cellspacing="0" style="width: 100%; border-collapse: collapse; border-color: #F8BBD0;">
            <thead style="background-color: #EC407A; color: white;">
              <tr>
                <th style="text-align: left; padding: 10px;">Producto</th>
                <th style="padding: 10px;">Cantidad</th>
                <th style="padding: 10px;">Precio Unit.</th>
                <th style="padding: 10px;">Subtotal</th>
              </tr>
            </thead>
            <tbody>
              ${productos.map((p) {
                final double precio = (p['precio'] as num).toDouble();
                final int cantidad = p['cantidad'] is int ? p['cantidad'] as int : int.tryParse(p['cantidad'].toString()) ?? 1;
                final subtotal = precio * cantidad;
                return """
                <tr style="text-align: center; border-bottom: 1px solid #F8BBD0;">
                  <td style="text-align: left; padding: 8px;">${p['nombre_product']}</td>
                  <td style="padding: 8px;">$cantidad</td>
                  <td style="padding: 8px;">\$${precio.toStringAsFixed(2)} MXN</td>
                  <td style="padding: 8px; font-weight: bold; color: #EC407A;">\$${subtotal.toStringAsFixed(2)} MXN</td>
                </tr>
                """;
              }).join('')}
            </tbody>
          </table>

          <div style="text-align: right; margin-top: 20px; padding: 15px; background: #FFF2F5; border-radius: 12px;">
            <h2 style="color: #EC407A; margin: 0;">Total: \$${total.toStringAsFixed(2)} MXN</h2>
          </div>

          <p style="text-align: center; font-size: 12px; color: #777; margin-top: 20px;">
            Si tienes dudas o aclaraciones sobre tu pedido, responde a este correo.
          </p>
        </div>
      </body>
    </html>
    """;

    return sendEmail(destino, asunto, 'Gracias por tu compra en Mi Tiendita',
        htmlContent: htmlContent);
  }

  /// Código de verificación
  static Future<bool> sendVerificationTokenEmail(
    String destino,
    String verificationToken,
  ) async {
    final asunto = 'Código de Verificación para tu Compra';
    final mensaje = 'Tu código de verificación es: $verificationToken';
    final htmlContent = """
    <html>
      <body style="font-family: Roboto, sans-serif; color: #333; background: #FFF2F5; padding: 20px;">
        <div style="max-width: 600px; margin: auto; padding: 25px; border: 1px solid #F8BBD0; border-radius: 16px; background: white;">
          <h1 style="color: #EC407A; text-align: center;">🔐 Código de Verificación</h1>
          <p style="text-align: center;">Por favor, utiliza el siguiente código para completar tu acción:</p>
          <div style="background: #FFF2F5; border-radius: 12px; padding: 20px; margin: 15px 0;">
            <h2 style="color: #4caf50; text-align: center; font-size: 38px; letter-spacing: 10px; margin: 0;">$verificationToken</h2>
          </div>
          <footer style="text-align: center; font-size: 12px; color: #777; margin-top: 20px;">
            Si no solicitaste esta acción, ignora este correo.
          </footer>
        </div>
      </body>
    </html>
    """;

    return sendEmail(destino, asunto, mensaje, htmlContent: htmlContent);
  }

  /// Token de verificación para Registro de Usuario
  static Future<bool> sendRegistroTokenEmail(
    String destino,
    String token,
    String nombre,
  ) async {
    final asunto = '🌸 Código de Verificación de Registro - Mi App';
    final mensaje = 'Tu código de verificación de registro es: $token';
    final htmlContent = """
    <html>
      <body style="font-family: Roboto, sans-serif; color: #333; background: #FFF2F5; padding: 20px;">
        <div style="max-width: 600px; margin: auto; padding: 25px; border: 1px solid #F8BBD0; border-radius: 16px; background: white;">
          <h1 style="color: #EC407A; text-align: center;">🌸 ¡Bienvenid@, $nombre!</h1>
          <p style="text-align: center;">Gracias por registrarte. Ingresa este código para validar tu cuenta:</p>
          <div style="background: #FFF2F5; border-radius: 12px; padding: 20px; margin: 15px 0;">
            <h2 style="color: #EC407A; text-align: center; font-size: 38px; letter-spacing: 10px; margin: 0;">$token</h2>
          </div>
          <footer style="text-align: center; font-size: 12px; color: #777; margin-top: 20px;">
            Si no reconoces este registro, puedes ignorar este mensaje.
          </footer>
        </div>
      </body>
    </html>
    """;

    return sendEmail(destino, asunto, mensaje, htmlContent: htmlContent);
  }

  /// Código OTP de verificación (2FA Login)
  static Future<bool> sendOTPEmail(String destino, String otp, {int minutos = 5}) async {
    const asunto = '🔐 Código de verificación - ${AppConfig.appName}';
    const mensaje = 'Tu código de verificación es:';
    final htmlContent = """
    <html>
      <body style="font-family: Roboto, sans-serif; background:#FFF2F5; padding:20px;">
        <div style="max-width:500px; margin:auto; background:white; border-radius:20px;
                    border:2px solid #F8BBD0; padding:30px; text-align:center;">
          <h1 style="color:#EC407A;">🌸 Verificación de Identidad</h1>
          <p style="color:#555;">Ingresa este código para completar tu inicio de sesión:</p>
          <div style="background:#FFF2F5; border-radius:12px; padding:20px; margin:20px 0;">
            <h2 style="color:#EC407A; font-size:42px; letter-spacing:12px; margin:0;">$otp</h2>
          </div>
          <p style="color:#999; font-size:13px;">
            Este código expira en <strong>$minutos minutos</strong>.<br>
            Si no solicitaste este código, ignora este correo.
          </p>
        </div>
      </body>
    </html>
    """;
    return sendEmail(destino, asunto, mensaje, htmlContent: htmlContent);
  }
}
