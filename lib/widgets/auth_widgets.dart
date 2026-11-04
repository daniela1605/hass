import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Aviso visible solo en modo demostración (sin correo/SMS configurado).
class DemoCodigoBanner extends StatelessWidget {
  final String codigo;
  final String canal; // 'correo' | 'SMS'
  final VoidCallback? onUsar;

  const DemoCodigoBanner({super.key, required this.codigo, required this.canal, this.onUsar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_rounded, color: Color(0xFFF9A825)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Modo demostración: el $canal no está configurado.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF8D6E00))),
                const SizedBox(height: 2),
                Text('Código: $codigo',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF8D6E00))),
              ],
            ),
          ),
          if (onUsar != null)
            TextButton(onPressed: onUsar, child: const Text('Usar')),
        ],
      ),
    );
  }
}

/// Campo grande para códigos de 6 dígitos.
class CodigoField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onCompleto;
  final bool enabled;

  const CodigoField({super.key, required this.controller, this.onCompleto, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(fontSize: 30, letterSpacing: 12, fontWeight: FontWeight.bold, color: AppTheme.darkPink),
      decoration: const InputDecoration(hintText: '000000', counterText: ''),
      onChanged: (v) {
        if (v.length == 6) onCompleto?.call(v);
      },
    );
  }
}

/// Encabezado con ícono redondo para pantallas de autenticación.
class EncabezadoAuth extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;

  const EncabezadoAuth({super.key, required this.icono, required this.titulo, required this.subtitulo});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: AppTheme.primaryPink,
          child: Icon(icono, size: 34, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Text(titulo,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.darkPink)),
        const SizedBox(height: 6),
        Text(subtitulo, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted)),
      ],
    );
  }
}

/// Selector de canal (correo / SMS).
class SelectorCanal extends StatelessWidget {
  final bool sms; // canal actual
  final bool smsDisponible;
  final ValueChanged<bool> onCambio;
  final String correoOculto;
  final String telefonoOculto;

  const SelectorCanal({
    super.key,
    required this.sms,
    required this.smsDisponible,
    required this.onCambio,
    required this.correoOculto,
    required this.telefonoOculto,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: [
        ButtonSegment(value: false, icon: const Icon(Icons.email_outlined), label: Text(correoOculto, overflow: TextOverflow.ellipsis)),
        ButtonSegment(
          value: true,
          enabled: smsDisponible,
          icon: const Icon(Icons.sms_outlined),
          label: Text(smsDisponible ? telefonoOculto : 'Sin teléfono', overflow: TextOverflow.ellipsis),
        ),
      ],
      selected: {sms},
      onSelectionChanged: (s) => onCambio(s.first),
      showSelectedIcon: false,
    );
  }
}

/// Lista de requisitos de contraseña que se marcan al cumplirse.
class RequisitosPassword extends StatelessWidget {
  final List<String> requisitos;
  final String password;

  const RequisitosPassword({super.key, required this.requisitos, required this.password});

  bool _cumple(String r) {
    if (r.startsWith('Mínimo')) {
      final n = int.tryParse(RegExp(r'\d+').firstMatch(r)?.group(0) ?? '0') ?? 0;
      return password.length >= n;
    }
    if (r.contains('mayúscula')) return RegExp(r'[A-ZÁÉÍÓÚÑ]').hasMatch(password);
    if (r.contains('número')) return RegExp(r'\d').hasMatch(password);
    if (r.contains('símbolo')) return RegExp(r'[^A-Za-z0-9ÁÉÍÓÚáéíóúÑñ]').hasMatch(password);
    if (r.contains('letra')) return RegExp(r'[A-Za-zÁÉÍÓÚáéíóúÑñ]').hasMatch(password);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: requisitos.map((r) {
        final ok = _cumple(r);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                size: 16, color: ok ? Colors.green : AppTheme.textMuted),
            const SizedBox(width: 6),
            Text(r, style: TextStyle(fontSize: 12, color: ok ? Colors.green.shade700 : AppTheme.textMuted)),
          ]),
        );
      }).toList(),
    );
  }
}

void mostrarMensaje(BuildContext context, String texto, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(texto),
    backgroundColor: error ? Colors.red.shade400 : AppTheme.exito,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}
