import 'dart:async';
import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/otp_service.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';

/// Recuperación de contraseña en 3 pasos (aplica a todos los roles):
///  1. Correo o usuario  →  2. Código temporal  →  3. Nueva contraseña
/// La vigencia del código y la fuerza de la contraseña dependen del rol.
class RecuperarPasswordView extends StatefulWidget {
  final String? identificadorInicial;
  const RecuperarPasswordView({super.key, this.identificadorInicial});

  @override
  State<RecuperarPasswordView> createState() => _RecuperarPasswordViewState();
}

class _RecuperarPasswordViewState extends State<RecuperarPasswordView> {
  int _paso = 0;
  final _idCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  bool _sms = false;
  bool _cargando = false;
  bool _oculta = true;
  String? _error;
  Usuario? _cuenta; // solo para mostrar requisitos; nunca se revela si no existe
  EnvioCodigo? _envio;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _idCtrl.text = widget.identificadorInicial ?? '';
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _paso == 1) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _idCtrl.dispose();
    _codigoCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  PoliticaRol get _politica => PoliticaRol.de(_cuenta?.rol ?? 'lector');

  // Paso 1 → enviar código
  Future<void> _solicitar() async {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Escribe tu correo o tu nombre de usuario.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    _cuenta = await AuthService.instance.buscarCuenta(id);
    final envio = await AuthService.instance
        .solicitarCodigoReset(id, _sms ? CanalOtp.sms : CanalOtp.email);
    if (!mounted) return;
    setState(() {
      _envio = envio;
      _cargando = false;
      _paso = 1;
      _codigoCtrl.clear();
    });
  }

  // Paso 2 → verificar código
  Future<void> _verificar() async {
    if (_codigoCtrl.text.trim().length != 6) {
      setState(() => _error = 'Ingresa los 6 dígitos.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    final r = await AuthService.instance.verificarCodigoReset(_idCtrl.text, _codigoCtrl.text);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _paso = 2;
      } else {
        _error = r.estado == EstadoVerificacion.inexistente
            ? 'El código no es válido para esa cuenta.'
            : r.mensaje;
        _codigoCtrl.clear();
      }
    });
  }

  // Paso 3 → guardar contraseña
  Future<void> _guardar() async {
    if (_passCtrl.text != _pass2Ctrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    final error = await AuthService.instance.restablecerPassword(_idCtrl.text, _passCtrl.text);
    if (!mounted) return;
    setState(() => _cargando = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    mostrarMensaje(context, '🔐 Contraseña actualizada. Ya puedes iniciar sesión.');
    Navigator.pop(context, _idCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EncabezadoAuth(
                icono: Icons.lock_reset_rounded,
                titulo: ['¿Olvidaste tu contraseña?', 'Revisa tu código', 'Crea tu nueva contraseña'][_paso],
                subtitulo: [
                  'Te enviaremos un código temporal para restablecerla.',
                  'Ingresa el código de 6 dígitos que recibiste.',
                  'Elige una contraseña segura que no hayas usado antes.',
                ][_paso],
              ),
              const SizedBox(height: 16),
              _indicadorPasos(),
              const SizedBox(height: 20),
              if (_paso == 0) ..._paso1(),
              if (_paso == 1) ..._paso2(),
              if (_paso == 2) ..._paso3(),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _indicadorPasos() {
    return Row(
      children: List.generate(3, (i) {
        final activo = i <= _paso;
        return Expanded(
          child: Container(
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: activo ? AppTheme.darkPink : AppTheme.cardBorderPink,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }

  List<Widget> _paso1() => [
        TextField(
          controller: _idCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Correo o nombre de usuario',
            prefixIcon: Icon(Icons.person_search_rounded),
          ),
        ),
        const SizedBox(height: 14),
        const Text('Enviar el código por:', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark)),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.email_outlined), label: Text('Correo')),
            ButtonSegment(value: true, icon: Icon(Icons.sms_outlined), label: Text('SMS')),
          ],
          selected: {_sms},
          onSelectionChanged: (s) => setState(() => _sms = s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 6),
        const Text('Si eliges SMS y la cuenta no tiene teléfono, se enviará por correo.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _cargando ? null : _solicitar,
          icon: _cargando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded),
          label: const Text('Enviar código'),
        ),
      ];

  List<Widget> _paso2() {
    final envio = _envio;
    final restante = envio?.vence.difference(DateTime.now());
    final demo = envio?.codigoDemo;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            envio == null
                ? 'Si la cuenta existe, enviamos un código a su correo o teléfono registrado.'
                : 'Si la cuenta existe, enviamos un código a ${envio.destinoOculto}.'
                    '${restante != null && !restante.isNegative ? '\nVence en ${restante.inMinutes}:${(restante.inSeconds % 60).toString().padLeft(2, '0')} min.' : '\nEl código venció.'}',
            style: const TextStyle(color: AppTheme.textDark),
          ),
        ),
      ),
      if (demo != null) ...[
        const SizedBox(height: 8),
        DemoCodigoBanner(
          codigo: demo,
          canal: envio?.canal == CanalOtp.sms ? 'SMS' : 'correo',
          onUsar: () => setState(() => _codigoCtrl.text = demo),
        ),
      ],
      const SizedBox(height: 16),
      CodigoField(controller: _codigoCtrl, onCompleto: (_) => _verificar()),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _cargando ? null : _verificar,
        icon: const Icon(Icons.verified_rounded),
        label: const Text('Verificar código'),
      ),
      TextButton(
        onPressed: _cargando ? null : () => setState(() => _paso = 0),
        child: const Text('Solicitar otro código'),
      ),
    ];
  }

  List<Widget> _paso3() => [
        if (_cuenta != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorderPink),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cuenta: ${_cuenta!.username} · ${_cuenta!.etiquetaRol}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkPink)),
                const SizedBox(height: 6),
                Text('Requisitos para el rol ${_cuenta!.etiquetaRol}:',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                RequisitosPassword(requisitos: _politica.requisitos, password: _passCtrl.text),
              ],
            ),
          ),
        const SizedBox(height: 14),
        TextField(
          controller: _passCtrl,
          obscureText: _oculta,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Nueva contraseña',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_oculta ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _oculta = !_oculta),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass2Ctrl,
          obscureText: _oculta,
          decoration: const InputDecoration(
            labelText: 'Confirmar contraseña',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _cargando ? null : _guardar,
          icon: _cargando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_rounded),
          label: const Text('Guardar contraseña'),
        ),
      ];
}
