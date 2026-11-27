import 'package:flutter/material.dart';
import '../repository/database_helper.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/mail_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';
import '../services/security_service.dart';
import '../services/usuario_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import 'home_view.dart';
import 'notificaciones_view.dart';

/// Perfil del usuario + preferencias personalizadas + seguridad.
class AjustesView extends StatefulWidget {
  const AjustesView({super.key});

  @override
  State<AjustesView> createState() => _AjustesViewState();
}

class _AjustesViewState extends State<AjustesView> {
  final _settings = AppSettings.instance;
  bool _biometriaDisponible = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_refrescar);
    AuthService.instance.biometriaDisponible().then((v) {
      if (mounted) setState(() => _biometriaDisponible = v);
    });
  }

  @override
  void dispose() {
    _settings.removeListener(_refrescar);
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final u = Sesion.instance.usuario!;
    final bioActiva = _settings.biometriaUsuarioId == u.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('👤 Mi perfil'),
        actions: const [NotificacionesBoton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Perfil ─────────────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppTheme.primaryPink,
                    child: Text(u.nombre.isNotEmpty ? u.nombre[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.nombre,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                        Text('@${u.username}', style: TextStyle(color: AppTheme.darkPink)),
                        Text(u.email, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        if (u.tieneTelefono)
                          Text('Tel. ${u.telefonoOculto}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, children: [
                          _etiqueta(u.etiquetaRol),
                          _etiqueta(u.proveedor == 'google' ? 'Cuenta Google' : 'Cuenta local'),
                        ]),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar perfil',
                    icon: Icon(Icons.edit_rounded, color: AppTheme.darkPink),
                    onPressed: _editarPerfil,
                  ),
                ],
              ),
            ),
          ),

          // ── Apariencia ────────────────────────────────────────────────────
          _titulo('Apariencia', Icons.palette_outlined),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tema de color', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: Paleta.todas.map((p) {
                      final sel = p.id == _settings.paleta.id;
                      return GestureDetector(
                        onTap: () => _settings.setPaleta(p),
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [p.primario, p.acento]),
                                shape: BoxShape.circle,
                                border: Border.all(color: sel ? AppTheme.textDark : Colors.white, width: sel ? 3 : 2),
                              ),
                              child: sel ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                            ),
                            const SizedBox(height: 4),
                            Text(p.nombre, style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.bold : null)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text('Tamaño del texto: ${(_settings.escalaTexto * 100).round()} %',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Slider(
                    value: _settings.escalaTexto,
                    min: 0.85,
                    max: 1.3,
                    divisions: 9,
                    activeColor: AppTheme.darkPink,
                    label: '${(_settings.escalaTexto * 100).round()} %',
                    onChanged: (v) => _settings.setEscalaTexto(v),
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      _settings.modoOscuro ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      color: AppTheme.darkPink,
                    ),
                    title: const Text('Modo Oscuro', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _settings.modoOscuro
                          ? 'Tema oscuro activado para descansar la vista'
                          : 'Tema claro con tonos pastel',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: _settings.modoOscuro,
                    activeColor: AppTheme.darkPink,
                    onChanged: (v) => _settings.setModoOscuro(v),
                  ),
                ],
              ),
            ),
          ),

          // ── Notificaciones ────────────────────────────────────────────────
          _titulo('Notificaciones', Icons.notifications_outlined),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.shield_outlined),
                  title: const Text('Alertas de seguridad'),
                  subtitle: const Text('Inicios de sesión y cambios de contraseña'),
                  value: _settings.notifSeguridad,
                  onChanged: _settings.setNotifSeguridad,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.shopping_bag_outlined),
                  title: const Text('Compras'),
                  subtitle: const Text('Confirmación de pedidos'),
                  value: _settings.notifCompras,
                  onChanged: _settings.setNotifCompras,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.local_offer_outlined),
                  title: const Text('Promociones y recomendaciones'),
                  value: _settings.notifPromociones,
                  onChanged: _settings.setNotifPromociones,
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Enviar notificación de prueba'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await NotificationService.instance.pedirPermiso();
                    await NotificationService.instance.notificar(
                      u.id!,
                      '🌸 ¡Hola, ${u.nombre.split(' ').first}!',
                      'Las notificaciones funcionan correctamente.',
                    );
                  },
                ),
              ],
            ),
          ),

          // ── Seguridad ─────────────────────────────────────────────────────
          _titulo('Seguridad', Icons.lock_outline_rounded),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint_rounded),
                  title: const Text('Acceso con huella / rostro / PIN'),
                  subtitle: Text(_biometriaDisponible
                      ? (bioActiva ? 'Activado para esta cuenta' : 'Entra sin escribir tu contraseña')
                      : 'Tu dispositivo no tiene biometría configurada'),
                  value: bioActiva,
                  onChanged: _biometriaDisponible ? (v) => _cambiarBiometria(v, u.id!) : null,
                ),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Verificación en 2 pasos'),
                  subtitle: Text('Siempre activa · Código por ${_settings.canal2fa == 'sms' ? 'SMS' : 'correo'}'),
                  trailing: DropdownButton<String>(
                    value: _settings.canal2fa,
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem(value: 'email', child: Text('Correo')),
                      DropdownMenuItem(value: 'sms', enabled: u.tieneTelefono, child: const Text('SMS')),
                      const DropdownMenuItem(value: 'totp', child: Text('Google Authenticator')),
                    ],
                    onChanged: (v) {
                      if (v != null) _settings.setCanal2fa(v);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Cambiar contraseña'),
                  subtitle: Text('Requisitos del rol ${u.etiquetaRol}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _cambiarPassword,
                ),
                const ListTile(
                  leading: Icon(Icons.enhanced_encryption_outlined),
                  title: Text('Cifrado de datos'),
                  subtitle: Text('Contraseñas con hash PBKDF2-SHA256 y teléfono cifrado con AES-256-GCM.'),
                ),
              ],
            ),
          ),

          // ── Servidor de Correo (Gmail) ────────────────────────────────────
          _titulo('Envío de Correo (Gmail)', Icons.mark_email_read_outlined),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.email_rounded, color: AppTheme.darkPink),
                  title: const Text('Correo emisor (Gmail)'),
                  subtitle: Text(_settings.smtpUsuario),
                  trailing: const Icon(Icons.lock_rounded, size: 18, color: Colors.grey),
                ),
                ListTile(
                  leading: Icon(Icons.key_rounded, color: AppTheme.darkPink),
                  title: const Text('Contraseña de aplicación (16 letras)'),
                  subtitle: Text(
                    _settings.correoConfigurado
                        ? '•••• •••• •••• •••• (Configurada y activa)'
                        : 'No configurada (Modo simulación)',
                    style: TextStyle(
                      color: _settings.correoConfigurado ? Colors.green[700] : Colors.orange[800],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _configurarSmtpDialog,
                    child: const Text('Configurar'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline_rounded, color: Colors.blue),
                  title: const Text('¿Dónde veo mi llave de 2 pasos de Google?'),
                  subtitle: const Text('Guía paso a paso para generar tu contraseña de 16 letras en Gmail'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _mostrarGuiaLlaveGoogle,
                ),
                ListTile(
                  leading: Icon(Icons.send_rounded, color: AppTheme.darkPink),
                  title: const Text('Enviar correo de prueba'),
                  subtitle: Text('Envía un correo de verificación a ${_settings.smtpUsuario}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _enviarCorreoPrueba,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => cerrarSesion(context),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _titulo(String t, IconData i) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(children: [
          Icon(i, size: 18, color: AppTheme.darkPink),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkPink, fontSize: 15)),
        ]),
      );

  Widget _etiqueta(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppTheme.softPinkBg, borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: TextStyle(fontSize: 11, color: AppTheme.darkPink, fontWeight: FontWeight.w600)),
      );

  Future<void> _configurarSmtpDialog() async {
    final passCtrl = TextEditingController(text: _settings.smtpPassword);
    final formKey = GlobalKey<FormState>();

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.mark_email_read_rounded, color: AppTheme.darkPink),
            const SizedBox(width: 8),
            const Text('Contraseña de Aplicación', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ingresa la contraseña de aplicación de 16 caracteres generada en tu cuenta de Google (${_settings.smtpUsuario}):',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: passCtrl,
                obscureText: false,
                decoration: const InputDecoration(
                  labelText: 'Clave de 16 letras',
                  hintText: 'abcd efgh ijkl mnop',
                  prefixIcon: Icon(Icons.vpn_key_rounded),
                ),
                validator: (v) {
                  final s = (v ?? '').replaceAll(' ', '').trim();
                  if (s.isEmpty) return 'Ingresa tu contraseña de aplicación.';
                  if (s.length != 16) return 'Debe tener exactamente 16 letras.';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                icon: const Icon(Icons.help_outline_rounded, size: 16),
                label: const Text('¿Cómo generar esta clave?', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _mostrarGuiaLlaveGoogle();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (guardado == true) {
      final claveLimpia = passCtrl.text.replaceAll(' ', '').trim();
      await _settings.setSmtpConfig(_settings.smtpUsuario, claveLimpia);
      if (mounted) {
        mostrarMensaje(context, '✅ Contraseña de aplicación guardada correctamente.');
      }
    }
  }

  void _mostrarGuiaLlaveGoogle() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.security_rounded, color: AppTheme.darkPink, size: 28),
            const SizedBox(width: 8),
            const Flexible(
              child: Text('¿Dónde veo mi llave de 2 pasos?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Google NO permite usar tu contraseña habitual para enviar correos desde apps externas. '
                'Debes generar una "Contraseña de Aplicación" de 16 letras siguiendo estos 3 pasos:',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              const Text(
                '1️⃣ Activa la Verificación en 2 Pasos:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
              ),
              const Text(
                'Entra a myaccount.google.com/security y asegúrate de que la "Verificación en dos pasos" esté activada.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              const Text(
                '2️⃣ Entra a Contraseñas de Aplicaciones:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
              ),
              const Text(
                'Ve directo al enlace oficial de Google: myaccount.google.com/apppasswords',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              const Text(
                '3️⃣ Crea la contraseña para la app:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
              ),
              const Text(
                'Escribe como nombre "Mi Tiendita" y presiona "Crear". Google te mostrará una ventana amarilla con 16 letras (ejemplo: abcd efgh ijkl mnop). Esa es tu llave.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Abrir Google App Passwords'),
                  onPressed: () async {
                    final uri = Uri.parse('https://myaccount.google.com/apppasswords');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarCorreoPrueba() async {
    mostrarMensaje(context, 'Enviando correo de prueba a ${_settings.smtpUsuario}...');
    final exito = await MailHelper.sendEmail(
      _settings.smtpUsuario,
      '🌸 Prueba de conexión exitosa - Mi Tiendita',
      '¡Hola Karla! Si recibes este correo, la configuración de Gmail y la contraseña de aplicación funcionan a la perfección.',
      htmlContent: '''
        <div style="font-family: Roboto, sans-serif; background: #FFF2F5; padding: 25px; border-radius: 16px; border: 1px solid #F8BBD0; max-width: 500px; margin: auto;">
          <h2 style="color: #EC407A; text-align: center;">🌸 ¡Conexión Exitosa!</h2>
          <p>Hola <strong>Karla</strong>,</p>
          <p>Tu correo <strong>${_settings.smtpUsuario}</strong> está correctamente vinculado con <strong>Mi Tiendita</strong>.</p>
          <div style="background: white; border-radius: 12px; padding: 15px; margin: 15px 0; border: 1px solid #F8BBD0;">
            <p style="margin: 4px 0;">✅ <strong>Envío de notas de compra:</strong> Habilitado</p>
            <p style="margin: 4px 0;">✅ <strong>Alertas de inicio de sesión:</strong> Habilitado</p>
            <p style="margin: 4px 0;">✅ <strong>Fecha y hora:</strong> ${DateTime.now()}</p>
          </div>
          <footer style="text-align: center; font-size: 11px; color: #777;">Mi Tiendita · Sistema de correo automático</footer>
        </div>
      ''',
    );

    if (mounted) {
      if (exito) {
        mostrarMensaje(context, '🎉 ¡Correo de prueba enviado con éxito a ${_settings.smtpUsuario}!');
      } else {
        mostrarMensaje(
          context,
          '⚠️ No se pudo enviar el correo. Revisa que tu contraseña de 16 letras sea correcta.',
          error: true,
        );
      }
    }
  }

  Future<void> _cambiarBiometria(bool activar, int usuarioId) async {
    final ok = await AuthService.instance.autenticarBiometria(
        activar ? 'Confirma para activar el acceso biométrico' : 'Confirma para desactivarlo');
    if (!ok) return;
    await _settings.setBiometriaUsuario(activar ? usuarioId : null);
    if (mounted) mostrarMensaje(context, activar ? 'Acceso biométrico activado' : 'Acceso biométrico desactivado');
  }

  Future<void> _editarPerfil() async {
    final u = Sesion.instance.usuario!;
    final nombresCtrl = TextEditingController(text: u.nombres);
    final paternoCtrl = TextEditingController(text: u.apellidoPaterno);
    final maternoCtrl = TextEditingController(text: u.apellidoMaterno);
    final telCtrl = TextEditingController(text: u.telefono);
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Editar perfil'),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombresCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre(s)', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: paternoCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Apellido paterno', prefixIcon: Icon(Icons.badge_outlined)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: maternoCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Apellido materno (opcional)', prefixIcon: Icon(Icons.badge_outlined)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: telCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono (para SMS)',
                prefixIcon: Icon(Icons.phone_iphone_rounded),
              ),
            ),
          ],
        ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (guardar != true) return;
    final tel = telCtrl.text.trim();
    final errorNombre = UsuarioService.validarParteNombre(nombresCtrl.text, 'El nombre') ??
        UsuarioService.validarParteNombre(paternoCtrl.text, 'El apellido paterno') ??
        UsuarioService.validarParteNombre(maternoCtrl.text, 'El apellido materno', obligatorio: false);
    if (errorNombre != null) {
      if (mounted) mostrarMensaje(context, errorNombre, error: true);
      return;
    }
    if (tel.isNotEmpty && tel.replaceAll(RegExp(r'\D'), '').length < 10) {
      if (mounted) mostrarMensaje(context, 'El teléfono debe tener al menos 10 dígitos.', error: true);
      return;
    }
    await DatabaseHelper.instance.actualizarPerfil(
      u.id!,
      nombres: nombresCtrl.text,
      apellidoPaterno: paternoCtrl.text,
      apellidoMaterno: maternoCtrl.text,
      telefono: tel,
    );
    await AuthService.instance.refrescarSesion();
    if (mounted) {
      setState(() {});
      mostrarMensaje(context, 'Perfil actualizado');
    }
  }

  Future<void> _cambiarPassword() async {
    final u = Sesion.instance.usuario!;
    final politica = PoliticaRol.de(u.rol);
    final actualCtrl = TextEditingController();
    final nuevaCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    String? error;
    var guardando = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Cambiar contraseña'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: actualCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: u.proveedor == 'google' ? 'Contraseña actual (opcional)' : 'Contraseña actual',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nuevaCtrl,
                  obscureText: true,
                  onChanged: (_) => setD(() {}),
                  decoration: const InputDecoration(labelText: 'Nueva contraseña'),
                ),
                const SizedBox(height: 8),
                RequisitosPassword(requisitos: politica.requisitos, password: nuevaCtrl.text),
                const SizedBox(height: 10),
                TextField(
                  controller: confCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirmar nueva contraseña'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: guardando
                  ? null
                  : () async {
                      if (nuevaCtrl.text != confCtrl.text) {
                        setD(() => error = 'Las contraseñas no coinciden.');
                        return;
                      }
                      setD(() => guardando = true);
                      final e = await AuthService.instance.cambiarPassword(u, actualCtrl.text, nuevaCtrl.text);
                      if (!ctx.mounted) return;
                      if (e != null) {
                        setD(() {
                          error = e;
                          guardando = false;
                        });
                        return;
                      }
                      Navigator.pop(ctx);
                      if (mounted) mostrarMensaje(context, '🔐 Contraseña actualizada');
                    },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
