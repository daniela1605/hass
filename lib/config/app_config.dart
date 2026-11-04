/// Configuración central de la app.
///
/// ⚠️ Aquí NO van contraseñas. Los valores se leen al compilar desde
/// `config/env.json` (que no se sube a git) usando:
///
///   flutter run --dart-define-from-file=config/env.json
///
/// En VS Code ya está configurado en `.vscode/launch.json` (solo presiona F5).
/// Plantilla con todas las claves: `config/env.example.json`.
///
/// Si una clave falta o está vacía, la app usa el valor por defecto y, para
/// correo/SMS, funciona en **modo demostración** (los códigos se muestran en
/// pantalla en lugar de enviarse).
class AppConfig {
  AppConfig._();

  // ── General ───────────────────────────────────────────────────────────────
  static const String appName =
      String.fromEnvironment('APP_NAME', defaultValue: 'Mi Tiendita');

  static const String productosApiUrl = String.fromEnvironment(
    'PRODUCTOS_API_URL',
    defaultValue: 'https://fakestoreapi.com/products',
  );

  /// Lada que se antepone a teléfonos de 10 dígitos (para SMS).
  static const String ladaPorDefecto =
      String.fromEnvironment('LADA_POR_DEFECTO', defaultValue: '+52');

  // ── Correo (Gmail + contraseña de aplicación) ─────────────────────────────
  // https://myaccount.google.com/apppasswords
  static const String smtpUsuario = String.fromEnvironment('SMTP_USUARIO');
  static const String smtpPassword = String.fromEnvironment('SMTP_PASSWORD');
  static const String smtpRemitente =
      String.fromEnvironment('SMTP_REMITENTE', defaultValue: 'Mi Tiendita 🌸');

  static bool get correoConfigurado =>
      smtpUsuario.contains('@') && smtpPassword.isNotEmpty;

  // ── SMS (Twilio, opcional) ────────────────────────────────────────────────
  // https://console.twilio.com → Account SID, Auth Token y número Twilio.
  static const String twilioAccountSid = String.fromEnvironment('TWILIO_ACCOUNT_SID');
  static const String twilioAuthToken = String.fromEnvironment('TWILIO_AUTH_TOKEN');
  static const String twilioNumero = String.fromEnvironment('TWILIO_NUMERO');

  static bool get smsConfigurado =>
      twilioAccountSid.isNotEmpty && twilioAuthToken.isNotEmpty && twilioNumero.isNotEmpty;

  // ── Usuarios de prueba (juan / pedro / ana) ──────────────────────────────
  // Pon correos a los que SÍ tengas acceso para recibir los códigos 2FA.
  // Tip Gmail: usa alias con "+" y todos llegan a tu bandeja:
  //   tu_correo+admin@gmail.com, tu_correo+editor@gmail.com, tu_correo+lector@gmail.com
  static const String demoAdminEmail =
      String.fromEnvironment('DEMO_ADMIN_EMAIL', defaultValue: 'juan@gmail.com');
  static const String demoEditorEmail =
      String.fromEnvironment('DEMO_EDITOR_EMAIL', defaultValue: 'pedro@gmail.com');
  static const String demoLectorEmail =
      String.fromEnvironment('DEMO_LECTOR_EMAIL', defaultValue: 'ana@gmail.com');

  /// Teléfonos opcionales de los usuarios de prueba (para probar SMS).
  static const String demoAdminTelefono = String.fromEnvironment('DEMO_ADMIN_TELEFONO');
  static const String demoEditorTelefono = String.fromEnvironment('DEMO_EDITOR_TELEFONO');
  static const String demoLectorTelefono = String.fromEnvironment('DEMO_LECTOR_TELEFONO');

  /// Resumen para depurar qué está configurado (sin mostrar secretos).
  static String get resumen =>
      'Correo: ${correoConfigurado ? 'configurado ($smtpUsuario)' : 'modo demo'} · '
      'SMS: ${smsConfigurado ? 'configurado' : 'modo demo'}';
}
