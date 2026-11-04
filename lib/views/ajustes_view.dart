import 'package:flutter/material.dart';
import '../repository/database_helper.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
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
