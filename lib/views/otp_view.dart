import 'dart:async';
import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/otp_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';

/// Paso 2 del inicio de sesión: código de verificación (2FA).
/// Devuelve `true` con Navigator.pop si el código es correcto.
class OtpView extends StatefulWidget {
  final Usuario usuario;
  const OtpView({super.key, required this.usuario});

  @override
  State<OtpView> createState() => _OtpViewState();
}

class _OtpViewState extends State<OtpView> {
  final _codigoCtrl = TextEditingController();
  late bool _sms;
  EnvioCodigo? _envio;
  bool _enviando = false;
  bool _verificando = false;
  String? _error;
  Timer? _timer;
  int _segReenvio = 0;
  Duration _restante = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sms = AppSettings.instance.canal2fa == 'sms' && widget.usuario.tieneTelefono;
    _enviar();
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
    setState(() {
      _enviando = true;
      _error = null;
    });
    final envio = await AuthService.instance
        .enviarOtpLogin(widget.usuario, _sms ? CanalOtp.sms : CanalOtp.email);
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
    final r = AuthService.instance.verificarOtpLogin(widget.usuario, codigo);
    if (!mounted) return;
    if (r.ok) {
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

  String get _tiempo =>
      '${_restante.inMinutes}:${(_restante.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final u = widget.usuario;
    final envio = _envio;
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
                subtitulo: 'Tu contraseña es correcta. Ahora ingresa el código de 6 dígitos que te enviamos.',
              ),
              const SizedBox(height: 20),
              const Text('¿Dónde quieres recibir el código?',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark)),
              const SizedBox(height: 8),
              SelectorCanal(
                sms: _sms,
                smsDisponible: u.tieneTelefono,
                correoOculto: u.emailOculto,
                telefonoOculto: u.telefonoOculto,
                onCambio: (v) {
                  if (_segReenvio > 0) {
                    mostrarMensaje(context, 'Espera $_segReenvio s para pedir otro código.', error: true);
                    return;
                  }
                  setState(() => _sms = v);
                  AppSettings.instance.setCanal2fa(v ? 'sms' : 'email');
                  _enviar();
                },
              ),
              const SizedBox(height: 16),
              if (_enviando)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              else if (envio != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(envio.canal == CanalOtp.sms ? Icons.sms_rounded : Icons.mark_email_read_rounded,
                            color: AppTheme.darkPink),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            envio.enviado
                                ? 'Código enviado a ${envio.destinoOculto}'
                                : 'Código generado para ${envio.destinoOculto}',
                            style: const TextStyle(color: AppTheme.textDark),
                          ),
                        ),
                        Text(_restante == Duration.zero ? 'Vencido' : _tiempo,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _restante.inSeconds < 30 ? Colors.red : AppTheme.darkPink)),
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
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _segReenvio > 0 || _enviando ? null : _enviar,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_segReenvio > 0 ? 'Reenviar código en $_segReenvio s' : 'Reenviar código'),
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
