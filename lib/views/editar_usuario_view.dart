import 'package:flutter/material.dart';
import '../controllers/usuario_controller.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/mail_helper.dart';
import '../services/notification_service.dart';
import '../services/otp_service.dart';
import '../services/usuario_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';

/// Edición de un usuario por parte del administrador:
/// nombre, correo, usuario, teléfono y rol; además desbloquear la cuenta
/// y enviarle un código para restablecer su contraseña.
///
/// Por seguridad el administrador NO puede ver ni escribir la contraseña de
/// otro usuario: solo puede enviarle un código para que él la cambie.
class EditarUsuarioView extends StatefulWidget {
  final Usuario usuario;
  final UsuarioController controller;

  const EditarUsuarioView({super.key, required this.usuario, required this.controller});

  @override
  State<EditarUsuarioView> createState() => _EditarUsuarioViewState();
}

class _EditarUsuarioViewState extends State<EditarUsuarioView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombresCtrl;
  late final TextEditingController _paternoCtrl;
  late final TextEditingController _maternoCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _telefonoCtrl;
  late String _rol;
  late bool _bloqueado;
  bool _guardando = false;
  String? _error;

  Usuario get _u => widget.usuario;
  bool get _esYo => _u.id == Sesion.instance.usuario?.id;

  static const _roles = [
    ('admin', 'Administrador', 'Control total: usuarios y productos', Icons.admin_panel_settings_rounded),
    ('editor', 'Editor', 'Agrega y elimina productos', Icons.edit_note_rounded),
    ('lector', 'Comprador', 'Consulta productos y compra', Icons.shopping_bag_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _nombresCtrl = TextEditingController(text: _u.nombres);
    _paternoCtrl = TextEditingController(text: _u.apellidoPaterno);
    _maternoCtrl = TextEditingController(text: _u.apellidoMaterno);
    _emailCtrl = TextEditingController(text: _u.email);
    _usernameCtrl = TextEditingController(text: _u.username);
    _telefonoCtrl = TextEditingController(text: _u.telefono);
    _rol = _u.rol;
    _bloqueado = _u.estaBloqueado;
  }

  @override
  void dispose() {
    _nombresCtrl.dispose();
    _paternoCtrl.dispose();
    _maternoCtrl.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });

    final emailNuevo = _emailCtrl.text.trim().toLowerCase();
    final cambios = <String>[
      if (_nombresCtrl.text.trim() != _u.nombres) 'nombre(s)',
      if (_paternoCtrl.text.trim() != _u.apellidoPaterno) 'apellido paterno',
      if (_maternoCtrl.text.trim() != _u.apellidoMaterno) 'apellido materno',
      if (emailNuevo != _u.email.toLowerCase()) 'correo',
      if (_usernameCtrl.text.trim().toLowerCase() != _u.username) 'usuario',
      if (_telefonoCtrl.text.trim() != _u.telefono) 'teléfono',
      if (_rol != _u.rol) 'rol',
    ];
    if (cambios.isEmpty) {
      setState(() => _guardando = false);
      Navigator.pop(context, false);
      return;
    }

    final error = await widget.controller.editarUsuario(
      _u.id!,
      nombres: _nombresCtrl.text,
      apellidoPaterno: _paternoCtrl.text,
      apellidoMaterno: _maternoCtrl.text,
      email: emailNuevo,
      username: _usernameCtrl.text,
      telefono: _telefonoCtrl.text,
      rol: _rol,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _guardando = false;
        _error = error;
      });
      return;
    }

    // Avisar al usuario (al correo anterior y, si cambió, también al nuevo).
    final detalle = 'Un administrador actualizó tu cuenta: ${cambios.join(', ')}.';
    MailHelper.sendSecurityAlertEmail(_u.email, 'Tu cuenta fue actualizada', detalle);
    if (emailNuevo != _u.email.toLowerCase()) {
      MailHelper.sendSecurityAlertEmail(emailNuevo, 'Tu cuenta fue actualizada', detalle);
    }
    await NotificationService.instance.notificar(
      _u.id!, 'Cuenta actualizada', detalle, tipo: 'seguridad');

    if (_esYo) await AuthService.instance.refrescarSesion();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _desbloquear() async {
    await widget.controller.desbloquearUsuario(_u.id!);
    if (!mounted) return;
    setState(() => _bloqueado = false);
    mostrarMensaje(context, '🔓 Cuenta desbloqueada');
  }

  Future<void> _enviarCodigoReset() async {
    final envio = await AuthService.instance.solicitarCodigoReset(_u.email, CanalOtp.email);
    if (!mounted) return;
    if (envio == null) {
      mostrarMensaje(context, 'No se encontró la cuenta.', error: true);
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Código enviado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(envio.enviado
                ? 'Se envió un código a ${envio.destinoOculto}.'
                : 'El correo no está configurado.'),
            const SizedBox(height: 8),
            Text(
              'Pide a ${_u.nombre.split(' ').first} que abra "¿Olvidaste tu contraseña?", '
              'escriba "${_u.username}" y use el código para crear su nueva contraseña.',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            if (envio.codigoDemo case final demo?) ...[
              const SizedBox(height: 10),
              DemoCodigoBanner(codigo: demo, canal: 'correo'),
            ],
          ],
        ),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );
  }

  InputDecoration _deco(String label, IconData icono, {String? helper}) => InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: Icon(icono, color: AppTheme.primaryPink),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar usuario')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Encabezado
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppTheme.primaryPink,
                    child: Text(_u.nombre.isNotEmpty ? _u.nombre[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ID #${_u.id} · ${_u.proveedor == 'google' ? 'Cuenta Google' : 'Cuenta local'}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        Text(_u.nombre,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                        if (_esYo)
                          Text('Esta es tu cuenta', style: TextStyle(fontSize: 12, color: AppTheme.darkPink)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Datos
              TextFormField(
                controller: _nombresCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: _deco('Nombre(s)', Icons.person_outline_rounded),
                validator: (v) => UsuarioService.validarParteNombre(v, 'El nombre'),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _paternoCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Apellido paterno'),
                      validator: (v) => UsuarioService.validarParteNombre(v, 'El apellido paterno'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _maternoCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Apellido materno', helperText: 'Opcional'),
                      validator: (v) =>
                          UsuarioService.validarParteNombre(v, 'El apellido materno', obligatorio: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _deco('Correo electrónico', Icons.alternate_email_rounded,
                    helper: 'Aquí llegarán sus códigos de verificación'),
                validator: (v) => UsuarioService.regexEmail.hasMatch((v ?? '').trim())
                    ? null
                    : 'Correo no válido.',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _usernameCtrl,
                decoration: _deco('Nombre de usuario', Icons.badge_outlined),
                validator: (v) => UsuarioService.regexUsername.hasMatch((v ?? '').trim())
                    ? null
                    : '3-20 caracteres: letras, números, punto o guion bajo.',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: _deco('Teléfono (opcional)', Icons.phone_iphone_rounded,
                    helper: 'Para códigos por SMS'),
                validator: (v) {
                  final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  return d.isNotEmpty && d.length < 10 ? 'Debe tener al menos 10 dígitos.' : null;
                },
              ),

              // Rol
              const SizedBox(height: 22),
              const Text('Rol', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              if (_esYo)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('No puedes cambiar el rol de tu propia cuenta.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ),
              const SizedBox(height: 8),
              for (final r in _roles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _esYo ? null : () => setState(() => _rol = r.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _rol == r.$1 ? AppTheme.softPinkBg : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _rol == r.$1 ? AppTheme.darkPink : AppTheme.cardBorderPink,
                          width: _rol == r.$1 ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(r.$4, color: _rol == r.$1 ? AppTheme.darkPink : AppTheme.textMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.$2, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                                Text(r.$3, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                              ],
                            ),
                          ),
                          if (_rol == r.$1) Icon(Icons.check_circle_rounded, color: AppTheme.darkPink),
                        ],
                      ),
                    ),
                  ),
                ),

              // Seguridad de la cuenta
              const SizedBox(height: 14),
              const Text('Seguridad de la cuenta',
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(_bloqueado ? Icons.lock_rounded : Icons.lock_open_rounded,
                          color: _bloqueado ? Colors.red : Colors.green),
                      title: Text(_bloqueado ? 'Cuenta bloqueada' : 'Cuenta activa'),
                      subtitle: Text(_bloqueado
                          ? 'Bloqueada por intentos fallidos de inicio de sesión'
                          : 'Sin bloqueos'),
                      trailing: _bloqueado
                          ? TextButton(onPressed: _desbloquear, child: const Text('Desbloquear'))
                          : null,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.lock_reset_rounded, color: AppTheme.darkPink),
                      title: const Text('Enviar código para restablecer contraseña'),
                      subtitle: const Text('El usuario elige su nueva contraseña'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _enviarCodigoReset,
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded),
                  label: const Text('Guardar cambios'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
