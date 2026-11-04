import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controllers/usuario_controller.dart';
import '../models/usuario.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import 'home_view.dart';
import 'otp_view.dart';
import 'recuperar_password_view.dart';
import 'recuperar_usuario_view.dart';
import 'usuario_form_view.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _biometriaDisponible = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _revisarBiometria();
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _revisarBiometria() async {
    final disp = await AuthService.instance.biometriaDisponible();
    if (mounted) setState(() => _biometriaDisponible = disp);
  }

  bool get _mostrarBotonBiometria =>
      _biometriaDisponible && AppSettings.instance.biometriaUsuarioId != null;

  // ─── Inicio de sesión: usuario/correo + contraseña → código 2FA ──────────
  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final r = await AuthService.instance
          .validarCredenciales(_idController.text.trim(), _passwordController.text);
      if (!r.ok) {
        setState(() => _errorMsg = r.error);
        return;
      }
      if (!mounted) return;

      // Paso 2: código OTP por correo o SMS
      final verificado = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => OtpView(usuario: r.usuario!)),
      );
      if (verificado != true) {
        setState(() => _errorMsg = 'No se completó la verificación en 2 pasos.');
        return;
      }
      await _entrar(r.usuario!, 'password');
    } catch (e) {
      setState(() => _errorMsg = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    final r = await AuthService.instance.loginConGoogle();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!r.ok) {
      setState(() => _errorMsg = r.error);
      return;
    }
    await _entrar(r.usuario!, 'google');
  }

  Future<void> _loginBiometria() async {
    setState(() => _errorMsg = null);
    final r = await AuthService.instance.loginBiometrico();
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _errorMsg = r.error);
      return;
    }
    await _entrar(r.usuario!, 'biometria');
  }

  Future<void> _entrar(Usuario u, String metodo) async {
    await AuthService.instance.iniciarSesion(u, metodo: metodo);
    if (metodo != 'biometria') await _ofrecerBiometria(u);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeView()),
    );
  }

  /// Después del primer inicio de sesión ofrece activar huella / rostro.
  Future<void> _ofrecerBiometria(Usuario u) async {
    if (!_biometriaDisponible || AppSettings.instance.biometriaUsuarioId == u.id) return;
    final prefs = await SharedPreferences.getInstance();
    final clave = 'bio_ofrecida_${u.id}';
    if (prefs.getBool(clave) == true || !mounted) return;
    await prefs.setBool(clave, true);
    if (!mounted) return;

    final activar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(Icons.fingerprint_rounded, size: 48, color: AppTheme.darkPink),
        title: const Text('¿Entrar más rápido?'),
        content: const Text(
            'Activa el acceso con huella, rostro o PIN del dispositivo. Puedes cambiarlo después en Ajustes → Seguridad.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Activar')),
        ],
      ),
    );
    if (activar == true) {
      final ok = await AuthService.instance.autenticarBiometria('Confirma para activar el acceso biométrico');
      if (ok) await AppSettings.instance.setBiometriaUsuario(u.id);
    }
  }

  Future<void> _irRecuperarPassword() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => RecuperarPasswordView(identificadorInicial: _idController.text.trim()),
      ),
    );
    if (id != null && mounted) {
      setState(() {
        _idController.text = id;
        _passwordController.clear();
        _errorMsg = null;
      });
    }
  }

  Future<void> _irRegistro() async {
    final res = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => UsuarioFormView(controller: UsuarioController()),
      ),
    );
    if (res == true && mounted) {
      mostrarMensaje(context, '🌸 ¡Cuenta creada! Ahora puedes iniciar sesión.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softPinkBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppTheme.primaryPink,
                  child: const Icon(Icons.lock_person_rounded, size: 38, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text('Bienvenida 🌸',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.darkPink, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Inicia sesión para continuar', style: TextStyle(color: AppTheme.textMuted)),
                const SizedBox(height: 16),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Form(
                      key: _formKey,
                      child: AutofillGroup(
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _idController,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.username, AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Correo o usuario',
                                prefixIcon: const Icon(Icons.person_outline_rounded),
                                suffixIcon: _idController.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () => setState(() => _idController.clear()),
                                      ),
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Escribe tu correo o nombre de usuario'
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _chip('Insertar @', () => _agregarTexto('@')),
                                const SizedBox(width: 8),
                                _chip('+ @gmail.com', () {
                                  final t = _idController.text.split('@').first;
                                  _ponerTexto('$t@gmail.com');
                                }),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => _iniciarSesion(),
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword ? 'Mostrar' : 'Ocultar',
                                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'La contraseña es obligatoria' : null,
                            ),

                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                alignment: WrapAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () => Navigator.push(context,
                                        MaterialPageRoute(builder: (_) => const RecuperarUsuarioView())),
                                    child: Text('¿Olvidaste tu usuario?',
                                        style: TextStyle(color: AppTheme.darkPink, fontSize: 12.5)),
                                  ),
                                  TextButton(
                                    onPressed: _irRecuperarPassword,
                                    child: Text('¿Olvidaste tu contraseña?',
                                        style: TextStyle(
                                            color: AppTheme.darkPink,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12.5)),
                                  ),
                                ],
                              ),
                            ),

                            if (_errorMsg != null) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: Colors.red[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.red.shade200)),
                                child: Row(children: [
                                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(_errorMsg!,
                                          style: const TextStyle(color: Colors.red, fontSize: 13))),
                                ]),
                              ),
                              const SizedBox(height: 10),
                            ],

                            // Botón Iniciar Sesión (+ huella si está activada)
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      onPressed: _isLoading ? null : _iniciarSesion,
                                      icon: _isLoading
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(Icons.login),
                                      label: Text(_isLoading ? 'Verificando...' : 'Iniciar sesión'),
                                    ),
                                  ),
                                ),
                                if (_mostrarBotonBiometria) ...[
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    height: 48,
                                    width: 56,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        side: BorderSide(color: AppTheme.darkPink, width: 1.5),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      ),
                                      onPressed: _isLoading ? null : _loginBiometria,
                                      child: Icon(Icons.fingerprint_rounded, size: 30, color: AppTheme.darkPink),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: Divider(color: AppTheme.cardBorderPink)),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Text('o continúa con', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                                ),
                                Expanded(child: Divider(color: AppTheme.cardBorderPink)),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Inicio de sesión social
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  side: BorderSide(color: Colors.grey.shade300),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                onPressed: _isLoading ? null : _loginGoogle,
                                icon: const Text('G',
                                    style: TextStyle(
                                        fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4285F4))),
                                label: const Text('Continuar con Google',
                                    style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Registro público (siempre como comprador)
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: AppTheme.darkPink, width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                onPressed: _isLoading ? null : _irRegistro,
                                icon: Icon(Icons.person_add_alt_1_rounded, color: AppTheme.darkPink),
                                label: Text('Crear cuenta nueva',
                                    style: TextStyle(color: AppTheme.darkPink, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  _tarjetaUsuariosPrueba(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _agregarTexto(String t) => _ponerTexto('${_idController.text}$t');

  void _ponerTexto(String t) {
    setState(() {
      _idController.text = t;
      _idController.selection = TextSelection.collapsed(offset: t.length);
    });
  }

  Widget _chip(String texto, VoidCallback onTap) => ActionChip(
        visualDensity: VisualDensity.compact,
        backgroundColor: AppTheme.softPinkBg,
        side: BorderSide(color: AppTheme.cardBorderPink),
        label: Text(texto,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkPink)),
        onPressed: onTap,
      );

  /// Solo visible en modo debug (no aparece en la app publicada).
  Widget _tarjetaUsuariosPrueba() => Card(
        color: AppTheme.softPinkBg,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.info_outline, size: 16, color: AppTheme.darkPink),
                const SizedBox(width: 6),
                Text('Usuarios de prueba (solo debug)',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkPink, fontSize: 13)),
              ]),
              const SizedBox(height: 6),
              _hint('juan', 'admin'),
              _hint('pedro', 'editor'),
              _hint('ana', 'lector'),
              const Text('Contraseña: password123', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ],
          ),
        ),
      );

  Widget _hint(String usuario, String rol) => InkWell(
        onTap: () {
          setState(() {
            _idController.text = usuario;
            _passwordController.text = 'password123';
          });
        },
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_rounded, size: 14, color: AppTheme.darkPink),
              const SizedBox(width: 4),
              Text(usuario,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkPink,
                      decoration: TextDecoration.underline)),
              const SizedBox(width: 6),
              Text('($rol)', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ],
          ),
        ),
      );
}
