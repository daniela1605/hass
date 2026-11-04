import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/saldo_proveedor_controller.dart';
import '../theme/app_theme.dart';
import 'paypal_checkout_dialog.dart';

/// Formateador para fecha de vencimiento de tarjeta `MM/AA`
class MesAnioInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 4) d = d.substring(0, 4);
    final texto = d.length > 2 ? '${d.substring(0, 2)}/${d.substring(2)}' : d;
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Modal interactivo para **"Fondear / Recargar Saldo"** de la Bolsa con el
/// Proveedor GestoPago mediante:
/// - SPEI Directo
/// - Tarjeta Bancaria (16 dígitos, MM/AA, CVV 3-4 dígitos ocultos)
/// - PayPal In-App (`PayPalCheckoutDialog`)
/// Incluye además los botones de simulación requeridos para pruebas.
class FondearSaldoSheet extends StatefulWidget {
  final String emailUsuario;

  const FondearSaldoSheet({super.key, this.emailUsuario = ''});

  static Future<void> mostrar(BuildContext context, {String emailUsuario = ''}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FondearSaldoSheet(emailUsuario: emailUsuario),
    );
  }

  @override
  State<FondearSaldoSheet> createState() => _FondearSaldoSheetState();
}

class _FondearSaldoSheetState extends State<FondearSaldoSheet> {
  final _saldoCtrl = SaldoProveedorController.instance;
  final _formKey = GlobalKey<FormState>();
  final _montoCtrl = TextEditingController(text: '500.00');

  // Campos de Tarjeta de Crédito / Débito (estrictamente validados)
  final _numTarjetaCtrl = TextEditingController();
  final _titularCtrl = TextEditingController();
  final _vencimientoCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();

  String _metodo = 'spei'; // 'spei' | 'tarjeta' | 'paypal'
  bool _procesando = false;

  static const List<double> _montosRapidos = [250, 500, 1000, 2500, 5000];

  @override
  void dispose() {
    _montoCtrl.dispose();
    _numTarjetaCtrl.dispose();
    _titularCtrl.dispose();
    _vencimientoCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  double get _montoSeleccionado =>
      double.tryParse(_montoCtrl.text.trim()) ?? 0.0;

  Future<void> _ejecutarFondeo() async {
    if (!_formKey.currentState!.validate()) return;
    final monto = _montoSeleccionado;
    if (monto < 10 || monto > 50000) return;

    String etiquetaMetodo = 'SPEI Directo';
    String? folioExterno;

    if (_metodo == 'paypal') {
      final resPayPal = await PayPalCheckoutDialog.mostrar(
        context,
        monto: monto,
        concepto: 'Fondeo de Bolsa de Saldo GestoPago (idDist=1)',
        emailSugerido: widget.emailUsuario,
      );
      if (resPayPal == null || !mounted) return;
      etiquetaMetodo = 'PayPal In-App (${resPayPal.fuenteFondos})';
      folioExterno = resPayPal.payId;
    } else if (_metodo == 'tarjeta') {
      setState(() => _procesando = true);
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      final ultimos4 = _numTarjetaCtrl.text.substring(12);
      etiquetaMetodo = 'Tarjeta Bancaria •••• $ultimos4';
      folioExterno = 'GP-CARD-${100000 + Random().nextInt(899999)}';
    } else {
      setState(() => _procesando = true);
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      etiquetaMetodo = 'SPEI Directo (STP GestoPago)';
      folioExterno = 'GP-SPEI-${100000 + Random().nextInt(899999)}';
    }

    final mov = await _saldoCtrl.recargarSaldo(
      monto: monto,
      metodoPago: etiquetaMetodo,
      folioAprobacion: folioExterno,
    );

    if (!mounted) return;
    setState(() => _procesando = false);
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2E7D32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Text(
            '✅ Bolsa abonada: +\$${monto.toStringAsFixed(2)} MXN · Folio: ${mov.folio} · Nuevo Saldo: \$${_saldoCtrl.saldo.toStringAsFixed(2)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.softPinkBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: AppTheme.darkPink,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fondear Bolsa con Proveedor',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkPink,
                            ),
                          ),
                          ListenableBuilder(
                            listenable: _saldoCtrl,
                            builder: (_, _) => Text(
                              'Saldo actual: \$${_saldoCtrl.saldo.toStringAsFixed(2)} MXN',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Botones de Simulación rápida para Pruebas ───────────────
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFE082)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.science_rounded, size: 16, color: Color(0xFFF57F17)),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Controles de Simulación (Pruebas de Bolsa)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF8D6E00),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2E7D32),
                                side: const BorderSide(color: Color(0xFF2E7D32)),
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                              ),
                              onPressed: () async {
                                await _saldoCtrl.reiniciarSaldoDemo();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context)
                                  ..clearSnackBars()
                                  ..showSnackBar(
                                    const SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: Color(0xFF2E7D32),
                                      content: Text('🔄 Bolsa reiniciada a \$2,500.00 MXN'),
                                    ),
                                  );
                              },
                              icon: const Icon(Icons.restore_rounded, size: 16),
                              label: const Text(
                                'Reiniciar a \$2,500.00',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFC62828),
                                side: const BorderSide(color: Color(0xFFC62828)),
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                              ),
                              onPressed: () async {
                                await _saldoCtrl.simularSaldoCero();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context)
                                  ..clearSnackBars()
                                  ..showSnackBar(
                                    const SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: Color(0xFFC62828),
                                      content: Text('⚠️ Simulación activa: Saldo en \$0.00 MXN'),
                                    ),
                                  );
                              },
                              icon: const Icon(Icons.money_off_csred_rounded, size: 16),
                              label: const Text(
                                'Simular Saldo \$0.00',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Monto a abonar ───────────────────────────────────────────
                const Text(
                  'Monto a abonar (MXN)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in _montosRapidos)
                      ChoiceChip(
                        label: Text('\$${m.toStringAsFixed(0)}'),
                        selected: _montoSeleccionado == m,
                        selectedColor: AppTheme.cardBorderPink,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: _montoSeleccionado == m
                              ? AppTheme.darkPink
                              : AppTheme.textDark,
                        ),
                        onSelected: (_) =>
                            setState(() => _montoCtrl.text = m.toStringAsFixed(2)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _montoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Importe a fondear (\$10.00 - \$50,000.00 MXN)',
                    prefixIcon: Icon(Icons.attach_money_rounded),
                    suffixText: 'MXN',
                  ),
                  validator: (v) {
                    final val = double.tryParse((v ?? '').trim());
                    if (val == null || val < 10.0 || val > 50000.0) {
                      return 'Ingresa un monto entre \$10.00 y \$50,000.00 MXN';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // ── Método de Fondeo ─────────────────────────────────────────
                const Text(
                  'Selecciona el medio de abono',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _chipMetodoFondeo(
                        id: 'spei',
                        titulo: 'SPEI Directo',
                        icono: Icons.account_balance_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _chipMetodoFondeo(
                        id: 'tarjeta',
                        titulo: 'Tarjeta Bancaria',
                        icono: Icons.credit_card_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _chipMetodoFondeo(
                        id: 'paypal',
                        titulo: 'PayPal In-App',
                        icono: Icons.account_balance_wallet_rounded,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                if (_metodo == 'spei') _vistaSpei(),
                if (_metodo == 'tarjeta') _vistaTarjeta(),
                if (_metodo == 'paypal') _vistaPayPal(),

                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _procesando ? null : _ejecutarFondeo,
                    icon: _procesando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_card_rounded),
                    label: Text(
                      _procesando
                          ? 'Acreditando saldo...'
                          : _metodo == 'paypal'
                              ? 'Continuar con PayPal In-App'
                              : 'Abonar \$${_montoSeleccionado.toStringAsFixed(2)} MXN a mi Bolsa',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipMetodoFondeo({
    required String id,
    required String titulo,
    required IconData icono,
  }) {
    final sel = _metodo == id;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _metodo = id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: sel ? AppTheme.softPinkBg : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? AppTheme.darkPink : AppTheme.cardBorderPink,
            width: sel ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icono,
              color: sel ? AppTheme.darkPink : AppTheme.textMuted,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              titulo,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                color: sel ? AppTheme.darkPink : AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaSpei() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.softPinkBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorderPink),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CLABE Concentradora STP · GestoPago:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
              color: AppTheme.textDark,
            ),
          ),
          SizedBox(height: 4),
          SelectableText(
            '646 180 1570 0000 0018',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              color: AppTheme.textDark,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Beneficiario: GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V. · El folio de abono se genera automáticamente al confirmar.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _vistaTarjeta() {
    return Column(
      children: [
        TextFormField(
          controller: _numTarjetaCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(16),
          ],
          decoration: const InputDecoration(
            labelText: 'Número de tarjeta (16 dígitos)',
            prefixIcon: Icon(Icons.credit_card_rounded),
            hintText: '4242424242424242',
          ),
          validator: (v) {
            final d = (v ?? '').trim();
            if (!RegExp(r'^\d{16}$').hasMatch(d)) {
              return 'Ingresa exactamente 16 dígitos numéricos';
            }
            return null;
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _vencimientoCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [MesAnioInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Vencimiento (MM/AA)',
                  prefixIcon: Icon(Icons.calendar_today_rounded),
                  hintText: '12/28',
                ),
                validator: (v) {
                  final val = (v ?? '').trim();
                  if (!RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$').hasMatch(val)) {
                    return 'Formato MM/AA';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _cvvCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: 'CVV (3-4 dígitos)',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
                validator: (v) {
                  final val = (v ?? '').trim();
                  if (!RegExp(r'^\d{3,4}$').hasMatch(val)) {
                    return '3 o 4 dígitos';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _vistaPayPal() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.account_balance_wallet_rounded,
            color: Color(0xFF003087),
            size: 30,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Al continuar se abrirá la pasarela interactiva PayPal In-App de 3 pasos para autorizar el fondeo inmediato.',
              style: TextStyle(fontSize: 12, color: Color(0xFF003087)),
            ),
          ),
        ],
      ),
    );
  }
}
