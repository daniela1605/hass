import 'package:flutter/material.dart';
import '../controllers/usuario_controller.dart';
import '../models/usuario.dart';
import '../services/otp_service.dart';
import '../services/security_service.dart';
import '../services/usuario_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';

class UsuarioFormView extends StatefulWidget {
  final UsuarioController controller;

  /// `true` cuando lo abre un administrador: puede elegir el rol y no se
  /// pide código de verificación. En el registro público el rol es "lector".
  final bool esAdmin;

  const UsuarioFormView({super.key, required this.controller, this.esAdmin = false});

  @override
  State<UsuarioFormView> createState() => _UsuarioFormViewState();
}

class _UsuarioFormViewState extends State<UsuarioFormView> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nombresCtrl = TextEditingController();
  final TextEditingController _paternoCtrl = TextEditingController();
  final TextEditingController _maternoCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _telefonoCtrl = TextEditingController();
  bool _usernameEditado = false;

  String _rolSeleccionado = 'lector'; // Valor por defecto
  bool _obscurePassword = true;

  final List<Map<String, dynamic>> _roles = [
    {
      'id': 'admin',
      'label': 'Administrador (admin)',
      'desc': 'Control total del sistema',
      'icon': Icons.admin_panel_settings_rounded,
      'color': AppTheme.adminText,
      'bg': AppTheme.adminBg,
    },
    {
      'id': 'editor',
      'label': 'Editor (editor)',
      'desc': 'Permisos de edición de contenido',
      'icon': Icons.edit_note_rounded,
      'color': AppTheme.editorText,
      'bg': AppTheme.editorBg,
    },
    {
      'id': 'lector',
      'label': 'Lector (lector)',
      'desc': 'Permisos de solo consulta',
      'icon': Icons.visibility_rounded,
      'color': AppTheme.lectorText,
      'bg': AppTheme.lectorBg,
    },
  ];

  @override
  void dispose() {
    _nombresCtrl.dispose();
    _paternoCtrl.dispose();
    _maternoCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  void _sugerirUsername() {
    if (_usernameEditado) return;
    final base = _emailCtrl.text.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]'), '');
    _usernameCtrl.text = base;
  }

  Future<void> _guardarUsuario() async {
    widget.controller.limpiarMensajes();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final email = _emailCtrl.text.trim();
    final nombres = _nombresCtrl.text.trim();
    final paterno = _paternoCtrl.text.trim();
    final materno = _maternoCtrl.text.trim();
    final nombre = Usuario.componerNombre(nombres, paterno, materno);
    final username = _usernameCtrl.text.trim().toLowerCase();
    final telefono = _telefonoCtrl.text.trim();
    final pass = _passwordCtrl.text;
    final rol = widget.esAdmin ? _rolSeleccionado : 'lector';

    // Validaciones de negocio (correo/usuario repetidos, política del rol)
    final error = await UsuarioService().validarNuevo(
      nombres: nombres,
      apellidoPaterno: paterno,
      apellidoMaterno: materno,
      email: email,
      username: username,
      password: pass,
      rol: rol,
      telefono: telefono,
    );
    if (error != null) {
      if (mounted) mostrarMensaje(context, '❌ $error', error: true);
      return;
    }

    // ── Registro público: verificar el correo con un código ──
    if (!widget.esAdmin) {
      final envio = await OtpService.instance.enviar(
        proposito: 'registro',
        sujeto: email.toLowerCase(),
        nombre: nombre,
        email: email,
        vigencia: const Duration(minutes: 10),
      );
      if (!mounted) return;
      final verificado = await _showTokenDialog(envio, email);
      if (verificado != true) {
        if (mounted) {
          mostrarMensaje(context, '❌ No se verificó el correo. Registro cancelado.', error: true);
        }
        return;
      }
    }

    // ── Registrar usuario validado en SQLite (contraseña con hash) ──
    final exito = await widget.controller.registrarUsuario(
      nombres: nombres,
      apellidoPaterno: paterno,
      apellidoMaterno: materno,
      email: email,
      password: pass,
      rol: rol,
      username: username,
      telefono: telefono,
    );

    if (exito && mounted) {
      Navigator.pop(context, true);
    }
  }

  /// Diálogo para validar el correo. Devuelve `true` si el código es correcto.
  Future<bool?> _showTokenDialog(EnvioCodigo envio, String email) {
    final ctrl = TextEditingController();
    String? error;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          void validar() {
            final r = OtpService.instance.verificar('registro', email.toLowerCase(), ctrl.text);
            if (r.ok) {
              Navigator.pop(ctx, true);
            } else if (r.estado == EstadoVerificacion.incorrecto) {
              setD(() => error = r.mensaje);
            } else {
              Navigator.pop(ctx, false);
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.mark_email_read_rounded, color: AppTheme.darkPink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Verifica tu correo',
                      style: TextStyle(color: AppTheme.darkPink, fontWeight: FontWeight.bold, fontSize: 17)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    envio.enviado
                        ? 'Enviamos un código de 6 dígitos a:\n$email'
                        : 'Código generado para:\n$email',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  if (envio.codigoDemo != null) ...[
                    const SizedBox(height: 10),
                    DemoCodigoBanner(
                      codigo: envio.codigoDemo!,
                      canal: 'correo',
                      onUsar: () => setD(() => ctrl.text = envio.codigoDemo!),
                    ),
                  ],
                  const SizedBox(height: 12),
                  CodigoField(controller: ctrl),
                  if (error != null) ...[
                    const SizedBox(height: 6),
                    Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              ElevatedButton(onPressed: validar, child: const Text('Validar y registrar')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final isLoading = widget.controller.isLoading;
        final error = widget.controller.errorMessage;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.darkPink),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(widget.esAdmin ? 'Nuevo usuario' : 'Crear cuenta'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tarjeta informativa rosita
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.cardBorderPink, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.softPinkBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person_add_alt_1_rounded,
                            color: AppTheme.darkPink,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nuevo Registro',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Tus datos se guardan cifrados en el dispositivo',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Alerta de error si el correo ya existe o la BD falló
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEF9A9A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFC62828)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              error,
                              style: const TextStyle(
                                color: Color(0xFFC62828),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // 1. Nombre separado
                  const Text(
                    'Nombre(s)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nombresCtrl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'Ej. Juan Carlos',
                      prefixIcon: Icon(Icons.person_outline_rounded, color: AppTheme.primaryPink),
                    ),
                    validator: (v) => UsuarioService.validarParteNombre(v, 'El nombre'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Apellido paterno',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _paternoCtrl,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(hintText: 'Ej. Pérez'),
                              validator: (v) => UsuarioService.validarParteNombre(v, 'El apellido paterno'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Apellido materno',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _maternoCtrl,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(hintText: 'Opcional'),
                              validator: (v) =>
                                  UsuarioService.validarParteNombre(v, 'El apellido materno', obligatorio: false),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 2. Campo Email
                  const Text(
                    'Correo Electrónico',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => _sugerirUsername(),
                    decoration: InputDecoration(
                      hintText: 'Ej. juan@gmail.com',
                      prefixIcon: Icon(Icons.mail_outline_rounded, color: AppTheme.primaryPink),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Tooltip(
                          message: 'Insertar @',
                          child: InkWell(
                            onTap: () {
                              final text = _emailCtrl.text;
                              _emailCtrl.text = '$text@';
                              _emailCtrl.selection = TextSelection.fromPosition(
                                TextPosition(offset: _emailCtrl.text.length),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.cardBorderPink,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '@',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: AppTheme.darkPink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'El correo electrónico es obligatorio.';
                      }
                      if (!UsuarioService.regexEmail.hasMatch(val.trim())) {
                        return 'Ingresa un correo electrónico con formato válido.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.pink.shade50,
                        side: BorderSide(color: AppTheme.cardBorderPink),
                        label: Text('Insertar @', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkPink)),
                        onPressed: () {
                          final text = _emailCtrl.text;
                          _emailCtrl.text = '$text@';
                          _emailCtrl.selection = TextSelection.fromPosition(
                            TextPosition(offset: _emailCtrl.text.length),
                          );
                          _sugerirUsername();
                        },
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.pink.shade50,
                        side: BorderSide(color: AppTheme.cardBorderPink),
                        label: Text('+ @gmail.com', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkPink)),
                        onPressed: () {
                          final text = _emailCtrl.text.split('@').first;
                          _emailCtrl.text = '$text@gmail.com';
                          _emailCtrl.selection = TextSelection.fromPosition(
                            TextPosition(offset: _emailCtrl.text.length),
                          );
                          _sugerirUsername();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Nombre de usuario
                  const Text(
                    'Nombre de usuario',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _usernameCtrl,
                    onChanged: (_) => _usernameEditado = true,
                    decoration: InputDecoration(
                      hintText: 'Ej. juan.perez',
                      helperText: 'Podrás iniciar sesión con tu usuario o tu correo',
                      prefixIcon: Icon(Icons.badge_outlined, color: AppTheme.primaryPink),
                    ),
                    validator: (val) {
                      if (val == null || !UsuarioService.regexUsername.hasMatch(val.trim())) {
                        return '3-20 caracteres: letras, números, punto o guion bajo.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Teléfono (opcional, para SMS)
                  const Text(
                    'Teléfono (opcional)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _telefonoCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'Ej. 5512345678',
                      helperText: 'Para recibir códigos por SMS y recuperar tu usuario',
                      prefixIcon: Icon(Icons.phone_iphone_rounded, color: AppTheme.primaryPink),
                    ),
                    validator: (val) {
                      final d = (val ?? '').replaceAll(RegExp(r'\D'), '');
                      if (d.isNotEmpty && d.length < 10) return 'Debe tener al menos 10 dígitos.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // 3. Campo Contraseña
                  const Text(
                    'Contraseña',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      prefixIcon: Icon(Icons.lock_outline_rounded, color: AppTheme.primaryPink),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppTheme.textMuted,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'La contraseña es obligatoria.';
                      }
                      return PoliticaRol.de(widget.esAdmin ? _rolSeleccionado : 'lector')
                          .validarPassword(val);
                    },
                  ),
                  const SizedBox(height: 8),
                  RequisitosPassword(
                    requisitos: PoliticaRol.de(widget.esAdmin ? _rolSeleccionado : 'lector').requisitos,
                    password: _passwordCtrl.text,
                  ),

                  const SizedBox(height: 24),

                  // 4. Selector de Rol (solo administradores)
                  if (widget.esAdmin) ...[
                  const Text(
                    'Seleccionar Rol',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Column(
                    children: _roles.map((r) {
                      final isSelected = _rolSeleccionado == r['id'];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _rolSeleccionado = r['id'] as String;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected ? (r['bg'] as Color).withOpacity(0.4) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? (r['color'] as Color) : AppTheme.cardBorderPink,
                              width: isSelected ? 2 : 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: r['bg'] as Color,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  r['icon'] as IconData,
                                  color: r['color'] as Color,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r['label'] as String,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: isSelected ? (r['color'] as Color) : AppTheme.textDark,
                                      ),
                                    ),
                                    Text(
                                      r['desc'] as String,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Radio<String>(
                                value: r['id'] as String,
                                groupValue: _rolSeleccionado,
                                activeColor: AppTheme.darkPink,
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _rolSeleccionado = val);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  ] else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.lectorBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shopping_bag_outlined, color: AppTheme.lectorText),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tu cuenta será de tipo Comprador. Un administrador puede cambiar tu rol.',
                              style: TextStyle(fontSize: 12, color: AppTheme.lectorText),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 30),

                  // Botón Enviar
                  ElevatedButton(
                    onPressed: isLoading ? null : _guardarUsuario,
                    child: isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_rounded),
                              SizedBox(width: 8),
                              Text('Registrar'),
                            ],
                          ),
                  ),

                  const SizedBox(height: 12),

                  // Botón Cancelar
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
