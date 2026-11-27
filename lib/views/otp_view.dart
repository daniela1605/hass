import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/usuario.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/otp_service.dart';
import '../services/totp_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';

/// Paso 2 del inicio de sesión: código de verificación (2FA).
/// Soporta Correo, SMS y Google Authenticator (TOTP).
/// Devuelve `true` con Navigator.pop si el código es correcto.
class OtpView extends StatefulWidget {
  final Usuario usuario;
  const OtpView({super.key, required this.usuario});

  @override
  State<OtpView> createState() => _OtpViewState();
}

class _OtpViewState extends State<OtpView> {
  final _codigoCtrl = TextEditingController();
  late String _canal; // 'email' | 'sms' | 'totp'
  EnvioCodigo? _envio;
  bool _enviando = false;
  bool _verificando = false;
  String? _error;
  Timer? _timer;
  int _segReenvio = 0;
  Duration _restante = Duration.zero;

  late final String _totpSecret;

  @override
  void initState() {
    super.initState();
    _totpSecret = TotpHelper.secretForUser(widget.usuario.email);

    final prefCanal = AppSettings.instance.canal2fa;
    if (prefCanal == 'totp') {
      _canal = 'totp';
    } else if (prefCanal == 'sms' && widget.usuario.tieneTelefono) {
      _canal = 'sms';
    } else {
      _canal = 'email';
    }

    if (_canal != 'totp') {
      _enviar();
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codigoCtrl.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      _segReenvio = OtpService.instance.segundosParaReenviar('login', '${widget.usuario.id}');
      if (_envio != null) {
        final r = _envio!.vence.difference(DateTime.now());
        _restante = r.isNegative ? Duration.zero : r;
      }
    });
  }

  Future<void> _enviar() async {
    if (_canal == 'totp') return;

    setState(() {
      _enviando = true;
      _error = null;
    });
    final envio = await AuthService.instance.enviarOtpLogin(
      widget.usuario,
      _canal == 'sms' ? CanalOtp.sms : CanalOtp.email,
    );
    if (!mounted) return;
    setState(() {
      _envio = envio;
      _enviando = false;
      _codigoCtrl.clear();
    });
    _tick();
  }

  Future<void> _verificar() async {
    final codigo = _codigoCtrl.text.trim();
    if (codigo.length != 6) {
      setState(() => _error = 'Ingresa los 6 dígitos.');
      return;
    }
    setState(() {
      _verificando = true;
      _error = null;
    });

    if (_canal == 'totp') {
      await Future.delayed(const Duration(milliseconds: 300));
      final esValido = TotpHelper.verifyCode(_totpSecret, codigo);
      if (!mounted) return;
      if (esValido) {
        Sesion.instance.metodo = 'totp';
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _verificando = false;
        _error = 'Código de Authenticator incorrecto o expirado. Asegúrate de que tu reloj esté en hora.';
        _codigoCtrl.clear();
      });
      return;
    }

    final r = AuthService.instance.verificarOtpLogin(widget.usuario, codigo);
    if (!mounted) return;
    if (r.ok) {
      Sesion.instance.metodo = 'password';
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _verificando = false;
      _error = r.mensaje;
      _codigoCtrl.clear();
    });
    if (r.estado == EstadoVerificacion.agotado) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context, false);
    }
  }

  void _mostrarClaveTotpModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: AppTheme.darkPink, size: 28),
            const SizedBox(width: 8),
            const Flexible(child: Text('Configurar Google Authenticator', style: TextStyle(fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Abre la app Google Authenticator en tu teléfono.\n'
              '2. Toca el botón "+" y selecciona "Introducir clave de configuración".\n'
              '3. En "Nombre de la cuenta", escribe: Mi Tiendita.\n'
              '4. En "Tu clave", ingresa la siguiente clave secreta:',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.softPinkBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorderPink),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _totpSecret,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: 2,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, color: AppTheme.darkPink),
                    tooltip: 'Copiar clave',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _totpSecret));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('📋 Clave secreta copiada al portapapeles.'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tipo de clave: Basada en la hora (30 segundos).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
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

  String get _tiempo =>
      '${_restante.inMinutes}:${(_restante.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final u = widget.usuario;
    final envio = _envio;
    final liveTotp = TotpHelper.generateCode(_totpSecret);
    final secRestantesTotp = TotpHelper.secondsRemaining();

    return Scaffold(
      appBar: AppBar(title: const Text('Verificación en 2 pasos')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EncabezadoAuth(
                icono: Icons.verified_user_rounded,
                titulo: 'Confirma que eres tú',
                subtitulo: 'Tu contraseña es correcta. Elige cómo deseas recibir o ingresar tu código de 6 dígitos.',
              ),
              const SizedBox(height: 20),
              const Text(
                'Método de verificación:',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark),
              ),
              const SizedBox(height: 8),

              // SegmentedButton de 3 opciones: Correo / SMS / Google Authenticator
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'email',
                    icon: const Icon(Icons.email_outlined, size: 18),
                    label: Text(u.emailOculto, overflow: TextOverflow.ellipsis),
                  ),
                  ButtonSegment(
                    value: 'sms',
                    enabled: u.tieneTelefono,
                    icon: const Icon(Icons.sms_outlined, size: 18),
                    label: Text(u.tieneTelefono ? u.telefonoOculto : 'SMS', overflow: TextOverflow.ellipsis),
                  ),
                  const ButtonSegment(
                    value: 'totp',
                    icon: Icon(Icons.phonelink_lock_rounded, size: 18),
                    label: Text('Authenticator', overflow: TextOverflow.ellipsis),
                  ),
                ],
                selected: {_canal},
                onSelectionChanged: (s) {
                  final nuevoCanal = s.first;
                  if (nuevoCanal != 'totp' && _segReenvio > 0 && nuevoCanal != _canal) {
                    mostrarMensaje(context, 'Espera $_segReenvio s para pedir otro código.', error: true);
                    return;
                  }
                  setState(() {
                    _canal = nuevoCanal;
                    _error = null;
                  });
                  AppSettings.instance.setCanal2fa(nuevoCanal);
                  if (nuevoCanal != 'totp') {
                    _enviar();
                  }
                },
                showSelectedIcon: false,
              ),
              const SizedBox(height: 16),

              // ─── VISTA CUANDO EL CANAL ES GOOGLE AUTHENTICATOR ──────────
              if (_canal == 'totp') ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppTheme.primaryPink.withValues(alpha: 0.2),
                              child: Icon(Icons.security_rounded, color: AppTheme.darkPink),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Google Authenticator',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                                  ),
                                  Text(
                                    'Código de 6 dígitos basado en tiempo',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.info_outline_rounded, color: AppTheme.darkPink),
                              tooltip: 'Ver clave para escanear',
                              onPressed: _mostrarClaveTotpModal,
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        const Text(
                          'Código actual generado en vivo:',
                          style: TextStyle(fontSize: 13, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.softPinkBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.cardBorderPink),
                          ),
                          child: Text(
                            '${liveTotp.substring(0, 3)} ${liveTotp.substring(3)}',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 6,
                              color: AppTheme.darkPink,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.timer_outlined, size: 16, color: secRestantesTotp < 7 ? Colors.red : Colors.grey[700]),
                            const SizedBox(width: 4),
                            Text(
                              'Cambia en $secRestantesTotp segundos',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: secRestantesTotp < 7 ? Colors.red : Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.key_rounded, size: 18),
                                label: const Text('Ver mi llave'),
                                onPressed: _mostrarClaveTotpModal,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.bolt_rounded, size: 18),
                                label: const Text('Usar este código'),
                                onPressed: () {
                                  setState(() => _codigoCtrl.text = liveTotp);
                                  _verificar();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (_enviando) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              ] else if (envio != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          envio.canal == CanalOtp.sms ? Icons.sms_rounded : Icons.mark_email_read_rounded,
                          color: AppTheme.darkPink,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            envio.enviado
                                ? 'Código enviado a ${envio.destinoOculto}'
                                : 'Código generado para ${envio.destinoOculto}',
                            style: const TextStyle(color: AppTheme.textDark),
                          ),
                        ),
                        Text(
                          _restante == Duration.zero ? 'Vencido' : _tiempo,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _restante.inSeconds < 30 ? Colors.red : AppTheme.darkPink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (envio.codigoDemo case final demo?) ...[
                  const SizedBox(height: 8),
                  DemoCodigoBanner(
                    codigo: demo,
                    canal: envio.canal == CanalOtp.sms ? 'SMS' : 'correo',
                    onUsar: () => setState(() => _codigoCtrl.text = demo),
                  ),
                ],
              ],

              const SizedBox(height: 16),
              CodigoField(controller: _codigoCtrl, onCompleto: (_) => _verificar()),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _verificando || _enviando ? null : _verificar,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Verificar y entrar'),
              ),
              if (_canal != 'totp') ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _segReenvio > 0 || _enviando ? null : _enviar,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(_segReenvio > 0 ? 'Reenviar código en $_segReenvio s' : 'Reenviar código'),
                ),
              ],
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
