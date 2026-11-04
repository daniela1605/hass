import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';

/// Recuperación del nombre de usuario por correo o por teléfono (SMS).
class RecuperarUsuarioView extends StatefulWidget {
  const RecuperarUsuarioView({super.key});

  @override
  State<RecuperarUsuarioView> createState() => _RecuperarUsuarioViewState();
}

class _RecuperarUsuarioViewState extends State<RecuperarUsuarioView> {
  final _ctrl = TextEditingController();
  bool _porTelefono = false;
  bool _cargando = false;
  String? _resultado;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final dato = _ctrl.text.trim();
    if (_porTelefono && dato.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = 'Escribe un teléfono de al menos 10 dígitos.');
      return;
    }
    if (!_porTelefono && !dato.contains('@')) {
      setState(() => _error = 'Escribe un correo válido.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    final msg = await AuthService.instance.recuperarUsuario(dato);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _resultado = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar usuario')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EncabezadoAuth(
                icono: Icons.badge_rounded,
                titulo: '¿Olvidaste tu usuario?',
                subtitulo: 'Te enviaremos tu nombre de usuario y el tipo de cuenta (rol) asociado.',
              ),
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.email_outlined), label: Text('Por correo')),
                  ButtonSegment(value: true, icon: Icon(Icons.sms_outlined), label: Text('Por teléfono')),
                ],
                selected: {_porTelefono},
                onSelectionChanged: (s) => setState(() {
                  _porTelefono = s.first;
                  _ctrl.clear();
                  _resultado = null;
                  _error = null;
                }),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                keyboardType: _porTelefono ? TextInputType.phone : TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: _porTelefono ? 'Teléfono registrado' : 'Correo registrado',
                  hintText: _porTelefono ? '5512345678' : 'tu@correo.com',
                  prefixIcon: Icon(_porTelefono ? Icons.phone_iphone_rounded : Icons.alternate_email_rounded),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _cargando ? null : _enviar,
                icon: _cargando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: const Text('Enviar mi usuario'),
              ),
              if (_resultado != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.cardBorderPink),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mark_email_read_rounded, color: AppTheme.darkPink),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_resultado!, style: const TextStyle(color: AppTheme.textDark))),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Volver a iniciar sesión'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
