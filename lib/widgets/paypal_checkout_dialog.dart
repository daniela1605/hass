import 'dart:math';
import 'package:flutter/material.dart';

/// Resultado devuelto al completar el flujo de 3 pasos de [PayPalCheckoutDialog].
class PayPalCheckoutResult {
  final String payId; // Ej. PAYID-M4X9K2A-8839201
  final String emailCuenta;
  final String fuenteFondos; // 'Saldo PayPal' | 'Visa •••• 4242'
  final double montoMxn;
  final DateTime fecha;

  const PayPalCheckoutResult({
    required this.payId,
    required this.emailCuenta,
    required this.fuenteFondos,
    required this.montoMxn,
    required this.fecha,
  });

  String get resumen => 'PayPal ($fuenteFondos · $emailCuenta)';
}

/// Modal interactivo con diseño oficial de PayPal en 3 pasos:
/// 1. Login PayPal (con autocompletado de cuenta Sandbox de prueba)
/// 2. Revisión de Pago (comercio, monto en MXN, fuente de fondos y Protección al Comprador)
/// 3. Confirmación (procesa el pago y genera `PAYID-...`)
class PayPalCheckoutDialog extends StatefulWidget {
  final double monto;
  final String concepto;
  final String emailSugerido;
  final String comercio;

  const PayPalCheckoutDialog({
    super.key,
    required this.monto,
    required this.concepto,
    this.emailSugerido = '',
    this.comercio = 'GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V.',
  });

  static Future<PayPalCheckoutResult?> mostrar(
    BuildContext context, {
    required double monto,
    required String concepto,
    String emailSugerido = '',
  }) {
    return showDialog<PayPalCheckoutResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PayPalCheckoutDialog(
        monto: monto,
        concepto: concepto,
        emailSugerido: emailSugerido,
      ),
    );
  }

  @override
  State<PayPalCheckoutDialog> createState() => _PayPalCheckoutDialogState();
}

class _PayPalCheckoutDialogState extends State<PayPalCheckoutDialog> {
  static const Color _ppNavy = Color(0xFF003087);
  static const Color _ppBlue = Color(0xFF0070BA);
  static const Color _ppLightBg = Color(0xFFF5F7FA);

  int _paso = 1; // 1: Login, 2: Revisión, 3: Confirmación
  bool _cargando = false;
  bool _mostrarPass = false;

  final _formLoginKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
  final _passCtrl = TextEditingController();

  String _fuenteFondos = 'Saldo PayPal';
  String _payIdGenerado = '';

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(
      text: widget.emailSugerido.contains('@') ? widget.emailSugerido : '',
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _autocompletarSandbox() {
    setState(() {
      _emailCtrl.text = 'comprador.sandbox@paypal.com.mx';
      _passCtrl.text = 'SandboxPayPal#2026';
    });
  }

  Future<void> _avanzarARevision() async {
    if (!_formLoginKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _paso = 2;
    });
  }

  Future<void> _confirmarYPagar() async {
    setState(() => _cargando = true);
    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;

    final rnd = Random();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final bloque1 = List.generate(7, (_) => chars[rnd.nextInt(chars.length)]).join();
    final bloque2 = (1000000 + rnd.nextInt(8999999)).toString();
    _payIdGenerado = 'PAYID-$bloque1-$bloque2';

    setState(() {
      _cargando = false;
      _paso = 3;
    });
  }

  void _finalizarConExito() {
    Navigator.of(context).pop(
      PayPalCheckoutResult(
        payId: _payIdGenerado,
        emailCuenta: _emailCtrl.text.trim(),
        fuenteFondos: _fuenteFondos,
        montoMxn: widget.monto,
        fecha: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _encabezadoPayPal(),
              _indicadorPasos(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: KeyedSubtree(
                    key: ValueKey(_paso),
                    child: _construirPasoActual(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _encabezadoPayPal() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_ppNavy, _ppBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_wallet_rounded, color: _ppNavy, size: 18),
                SizedBox(width: 5),
                Text(
                  'PayPal',
                  style: TextStyle(
                    color: _ppNavy,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Checkout In-App Oficial',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  'Conexión cifrada TLS · Sandbox',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          if (!_cargando && _paso < 3)
            IconButton(
              tooltip: 'Cerrar',
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _indicadorPasos() {
    return Container(
      color: _ppLightBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _pasoChip(1, '1. Login'),
          const Expanded(child: Divider(indent: 6, endIndent: 6)),
          _pasoChip(2, '2. Revisión'),
          const Expanded(child: Divider(indent: 6, endIndent: 6)),
          _pasoChip(3, '3. Confirmación'),
        ],
      ),
    );
  }

  Widget _pasoChip(int numPaso, String label) {
    final activo = _paso == numPaso;
    final completado = _paso > numPaso;
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: completado
                ? const Color(0xFF2E7D32)
                : (activo ? _ppBlue : Colors.grey.shade400),
            child: completado
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : Text(
                    '$numPaso',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: activo ? FontWeight.bold : FontWeight.w500,
                color: activo ? _ppNavy : Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirPasoActual() {
    switch (_paso) {
      case 1:
        return _paso1Login();
      case 2:
        return _paso2Revision();
      default:
        return _paso3Confirmacion();
    }
  }

  // ─── PASO 1: LOGIN PAYPAL ──────────────────────────────────────────────────
  Widget _paso1Login() {
    return Form(
      key: _formLoginKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Inicia sesión en tu cuenta PayPal',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _ppNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Importe a autorizar: \$${widget.monto.toStringAsFixed(2)} MXN',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _ppBlue,
              side: const BorderSide(color: _ppBlue),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _autocompletarSandbox,
            icon: const Icon(Icons.bolt_rounded, size: 18),
            label: const Text(
              'Autocompletar cuenta Sandbox de prueba',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Correo electrónico de PayPal',
              prefixIcon: const Icon(Icons.email_outlined, color: _ppBlue),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            validator: (v) {
              final val = (v ?? '').trim();
              final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
              if (!emailRegex.hasMatch(val)) {
                return 'Ingresa un correo de PayPal válido';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passCtrl,
            obscureText: !_mostrarPass,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: _ppBlue),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _mostrarPass = !_mostrarPass),
                icon: Icon(_mostrarPass ? Icons.visibility_off : Icons.visibility),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            validator: (v) {
              if ((v ?? '').trim().length < 6) {
                return 'La contraseña debe tener al menos 6 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _ppBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: _cargando ? null : _avanzarARevision,
              child: _cargando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Continuar a Revisión de Pago'),
            ),
          ),
        ],
      ),
    );
  }

  // ─── PASO 2: REVISIÓN DE PAGO ──────────────────────────────────────────────
  Widget _paso2Revision() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _ppLightBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storefront_rounded, color: _ppNavy, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.comercio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: _ppNavy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.concepto,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
              ),
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total en MXN:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    '\$${widget.monto.toStringAsFixed(2)} MXN',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      color: _ppNavy,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Selecciona tu fuente de fondos:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _ppNavy),
        ),
        const SizedBox(height: 8),
        _opcionFuenteFondos(
          titulo: 'Saldo PayPal',
          subtitulo: 'Disponible: \$18,450.00 MXN · Sin comisiones',
          icono: Icons.account_balance_wallet_rounded,
        ),
        const SizedBox(height: 8),
        _opcionFuenteFondos(
          titulo: 'Visa •••• 4242',
          subtitulo: 'Tarjeta de Crédito / Débito vinculada',
          icono: Icons.credit_card_rounded,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: Color(0xFF2E7D32), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Protección al Comprador de PayPal activa para esta transacción en GestoPago.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF1B5E20)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: _cargando ? null : () => setState(() => _paso = 1),
              child: const Text('Atrás'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ppNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: _cargando ? null : _confirmarYPagar,
                  icon: _cargando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.lock_rounded, size: 18),
                  label: Text(
                    _cargando
                        ? 'Autorizando...'
                        : 'Pagar \$${widget.monto.toStringAsFixed(2)} MXN',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _opcionFuenteFondos({
    required String titulo,
    required String subtitulo,
    required IconData icono,
  }) {
    final sel = _fuenteFondos == titulo;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _fuenteFondos = titulo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFEBF3FA) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? _ppBlue : Colors.grey.shade300,
            width: sel ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icono, color: sel ? _ppBlue : Colors.grey.shade600),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: sel ? _ppNavy : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(
              sel ? Icons.radio_button_checked : Icons.radio_button_off,
              color: sel ? _ppBlue : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  // ─── PASO 3: CONFIRMACIÓN ──────────────────────────────────────────────────
  Widget _paso3Confirmacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: CircleAvatar(
            radius: 30,
            backgroundColor: Color(0xFFE8F5E9),
            child: Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 42),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '¡Pago Autorizado por PayPal!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: _ppNavy,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Cuenta: ${_emailCtrl.text.trim()}',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _ppLightBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Column(
            children: [
              _filaConfirmacion('ID de Transacción PayPal:', _payIdGenerado, dest: true),
              const SizedBox(height: 6),
              _filaConfirmacion('Fuente de fondos:', _fuenteFondos),
              const SizedBox(height: 6),
              _filaConfirmacion(
                'Monto pagado:',
                '\$${widget.monto.toStringAsFixed(2)} MXN',
                dest: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            onPressed: _finalizarConExito,
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Generar Comprobante Oficial'),
          ),
        ),
      ],
    );
  }

  Widget _filaConfirmacion(String k, String v, {bool dest = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            k,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: dest ? FontWeight.bold : FontWeight.w600,
              color: dest ? _ppNavy : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
