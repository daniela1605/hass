import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/saldo_proveedor_controller.dart';
import '../models/gestopago_models.dart';
import '../services/gestopago_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fondear_saldo_sheet.dart';
import '../widgets/paypal_checkout_dialog.dart';

/// Resultado de un pago autorizado a través del switch GestoPago.
class ResultadoPago {
  final String metodo; // 'saldo_proveedor' | 'paypal' | 'tarjeta' | 'wallet'
  final String descripcion; // Ej. "Visa •••• 4242" o "Saldo con Proveedor GestoPago"
  final String referencia; // Folio oficial retornado por el proveedor tras aprobarse
  final String estado; // 'aprobado' | 'pendiente'
  final ResultadoTransaccionGestoPago? ticketGestoPago;

  const ResultadoPago(
    this.metodo,
    this.descripcion,
    this.referencia,
    this.estado, {
    this.ticketGestoPago,
  });

  bool get pendiente => estado == 'pendiente';

  /// Texto corto para historial y correo.
  String get resumen =>
      '$descripcion · Folio $referencia${pendiente ? ' (pendiente)' : ''}';

  static String etiqueta(String metodo) =>
      const {
        'saldo_proveedor': 'Saldo GestoPago',
        'paypal': 'PayPal In-App',
        'tarjeta': 'Tarjeta Créd/Déb',
        'wallet': 'Apple Pay / Google Wallet',
        'transferencia': 'Transferencia SPEI',
        'efectivo': 'Efectivo en tienda',
      }[metodo] ??
      metodo;

  static IconData icono(String metodo) =>
      const {
        'saldo_proveedor': Icons.account_balance_wallet_rounded,
        'paypal': Icons.payments_rounded,
        'tarjeta': Icons.credit_card_rounded,
        'wallet': Icons.contactless_rounded,
        'transferencia': Icons.account_balance_rounded,
        'efectivo': Icons.payments_rounded,
      }[metodo] ??
      Icons.payment_rounded;
}

/// Pasarela de pago para Carrito de Compras conectada a la Bolsa de Saldo con
/// Proveedor (`SaldoProveedorController`), `PayPalCheckoutDialog` y `GestoPagoService`.
///
/// Cumple estrictamente:
/// - NUNCA muestra ni permite editar un Folio antes de que el pago sea aprobado.
/// - Valida obligatoriamente `saldo > 0` y `saldo >= monto` antes de autorizar.
/// - Permite elegir entre:
///   1. Saldo con Proveedor GestoPago
///   2. PayPal In-App (3 pasos)
///   3. Tarjeta de Crédito / Débito (16 dígitos, MM/AA, CVV 3-4 oculto)
///   4. Apple Pay / Google Wallet
class PagoView extends StatefulWidget {
  final double total;
  final String emailUsuario;

  const PagoView({super.key, required this.total, required this.emailUsuario});

  @override
  State<PagoView> createState() => _PagoViewState();
}

class _PagoViewState extends State<PagoView> {
  final _saldoCtrl = SaldoProveedorController.instance;
  String _metodo = 'saldo_proveedor';
  bool _procesando = false;
  String? _error;

  // Formulario de Tarjeta de Crédito / Débito
  final _formTarjeta = GlobalKey<FormState>();
  final _numeroCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _vigenciaCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _saldoCtrl.init();
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _nombreCtrl.dispose();
    _vigenciaCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  String get _totalStr => '\$${widget.total.toStringAsFixed(2)} MXN';
  String get _digitos => _numeroCtrl.text.replaceAll(RegExp(r'\D'), '');

  static String marca(String n) {
    if (n.startsWith('4')) return 'Visa';
    if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(n)) return 'Mastercard';
    if (RegExp(r'^3[47]').hasMatch(n)) return 'American Express';
    return 'Tarjeta';
  }

  String? _validarVigencia(String? v) {
    final val = (v ?? '').trim();
    if (!RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$').hasMatch(val)) {
      return 'Formato MM/AA';
    }
    return null;
  }

  void _abrirModalFondeo() {
    FondearSaldoSheet.mostrar(context, emailUsuario: widget.emailUsuario);
  }

  Future<void> _pagar() async {
    setState(() => _error = null);

    // 1. Validación estricta de fondos en la Bolsa GestoPago ("Sí o sí debe disponer de dinero")
    if (!_saldoCtrl.validarFondosConAlerta(
      context,
      montoRequerido: widget.total,
      conceptoOperacion: 'Compra de Carrito Mi Tiendita ($_totalStr)',
      onAbrirModalFondeo: _abrirModalFondeo,
    )) {
      return;
    }

    // 2. Validar campos si eligió Tarjeta
    if (_metodo == 'tarjeta' && !_formTarjeta.currentState!.validate()) return;

    if (_metodo == 'tarjeta' && _digitos == '4000000000000002') {
      setState(() {
        _error =
            'Pago rechazado por el banco emisor: tarjeta de prueba sin fondos.';
      });
      return;
    }

    String detalleMetodo = 'Saldo con Proveedor GestoPago';
    String? idPasarela;

    // 3. Si eligió PayPal In-App, abrir el modal interactivo de 3 pasos
    if (_metodo == 'paypal') {
      final resPayPal = await PayPalCheckoutDialog.mostrar(
        context,
        monto: widget.total,
        concepto: 'Compra de Carrito Mi Tiendita ($_totalStr)',
        emailSugerido: widget.emailUsuario,
      );
      if (resPayPal == null || !mounted) return;
      detalleMetodo = resPayPal.resumen;
      idPasarela = resPayPal.payId;
    } else if (_metodo == 'tarjeta') {
      final ultimos4 = _digitos.substring(12);
      detalleMetodo = '${marca(_digitos)} •••• $ultimos4';
    } else if (_metodo == 'wallet') {
      detalleMetodo = 'Apple Pay / Google Wallet';
    }

    setState(() => _procesando = true);

    try {
      final prodCarrito = const GestoPagoProducto(
        servicio: 'Mi Tiendita · GestoPago',
        producto: 'Liquidación de Carrito de Compras',
        idServicio: '19',
        idProducto: '1999',
        idCatTipoServicio: '19',
        tipoFront: '2',
        hasDigitoVerificador: false,
        precio: 0.0,
        showAyuda: false,
        tipoReferencia: 'a',
        legend:
            'Compra de artículos procesada por GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V. Conserve su folio oficial GP-AUTH para cualquier aclaración.',
      );

      final saldoRestante = _saldoCtrl.saldo -
          widget.total +
          SaldoProveedorController.comisionPorOperacion;

      final txResult = await GestoPagoService.instance.procesarTransaccion(
        producto: prodCarrito,
        referencia: widget.emailUsuario,
        monto: widget.total,
        metodoPago: _metodo,
        detalleMetodoPago: detalleMetodo,
        saldoRestanteProveedor: saldoRestante,
        idTransaccionPasarela: idPasarela,
      );

      await _saldoCtrl.descontarSaldo(
        monto: widget.total,
        concepto: 'Compra Carrito Mi Tiendita (${widget.emailUsuario})',
        folioOficial: txResult.folioAutorizacion,
        metodoPago: detalleMetodo,
      );

      if (!mounted) return;
      final resultado = ResultadoPago(
        _metodo,
        detalleMetodo,
        txResult.folioAutorizacion,
        'aprobado',
        ticketGestoPago: txResult,
      );
      Navigator.pop(context, resultado);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _procesando = false;
        _error = 'No se pudo procesar el pago: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_procesando,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            '💳 Pasarela de Pago GestoPago',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _saldoCtrl,
            builder: (context, _) {
              final suficiente =
                  _saldoCtrl.cuentaConFondosSuficientes(widget.total);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Tarjeta de Bolsa de Saldo con Proveedor ──────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: suficiente
                            ? [AppTheme.darkPink, const Color(0xFFAD1457)]
                            : [const Color(0xFFB71C1C), const Color(0xFFE53935)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_rounded,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bolsa de Saldo Proveedor GestoPago',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '\$${_saldoCtrl.saldo.toStringAsFixed(2)} MXN disponibles',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppTheme.darkPink,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                              ),
                              onPressed: _abrirModalFondeo,
                              icon: const Icon(Icons.add_card_rounded, size: 16),
                              label: const Text(
                                'Fondear',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!suficiente) ...[
                          const SizedBox(height: 8),
                          const Text(
                            '⚠️ Saldo insuficiente para cubrir el total del carrito. Recarga tu bolsa antes de pagar.',
                            style: TextStyle(
                              color: Color(0xFFFFF59D),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Total a pagar ────────────────────────────────────────
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text(
                              'Total a pagar',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                          Text(
                            _totalStr,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkPink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Selección de los 4 Métodos de Pago ───────────────────
                  const Text(
                    'Elige el método de pago',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.35,
                    children: [
                      for (final m in const [
                        'saldo_proveedor',
                        'paypal',
                        'tarjeta',
                        'wallet',
                      ])
                        _opcionMetodo(m),
                    ],
                  ),
                  const SizedBox(height: 16),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey(_metodo),
                      child: _detalleMetodo(),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _procesando ? null : _pagar,
                      icon: _procesando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.lock_rounded),
                      label: Text(
                        _procesando ? 'Autorizando con GestoPago...' : _textoBoton,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 14,
                        color: AppTheme.textMuted,
                      ),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'El Folio de Autorización oficial se entrega al aprobarse el pago',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String get _textoBoton {
    switch (_metodo) {
      case 'paypal':
        return 'Continuar con PayPal In-App $_totalStr';
      case 'wallet':
        return 'Pagar con Wallet $_totalStr';
      default:
        return 'Autorizar Pago $_totalStr';
    }
  }

  Widget _opcionMetodo(String m) {
    final sel = _metodo == m;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _procesando
          ? null
          : () => setState(() {
                _metodo = m;
                _error = null;
              }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: sel ? AppTheme.softPinkBg : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? AppTheme.darkPink : AppTheme.cardBorderPink,
            width: sel ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              ResultadoPago.icono(m),
              color: sel ? AppTheme.darkPink : AppTheme.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ResultadoPago.etiqueta(m),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                  color: sel ? AppTheme.darkPink : AppTheme.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detalleMetodo() {
    switch (_metodo) {
      case 'saldo_proveedor':
        return _vistaSaldoProveedor();
      case 'paypal':
        return _vistaPayPal();
      case 'wallet':
        return _vistaWallet();
      default:
        return _vistaTarjeta();
    }
  }

  Widget _vistaSaldoProveedor() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.softPinkBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorderPink),
      ),
      child: const Row(
        children: [
          Icon(Icons.bolt_rounded, color: AppTheme.textDark, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'El cargo se descontará directamente de tu Bolsa con Proveedor GestoPago y acreditará +\$2.50 MXN de comisión al comercio.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaPayPal() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.account_balance_wallet_rounded,
            color: Color(0xFF003087),
            size: 34,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Al confirmar se abrirá el modal interactivo de PayPal In-App (1. Login Sandbox → 2. Revisión de Pago → 3. Confirmación PAYID).',
              style: TextStyle(color: Color(0xFF003087), fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaWallet() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.contactless_rounded, color: Color(0xFF6A1B9A), size: 32),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Pago rápido mediante token criptográfico de Apple Pay / Google Wallet.',
              style: TextStyle(color: Color(0xFF4A148C), fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaTarjeta() {
    final d = _digitos;
    final visibles = d.isEmpty ? '•••• •••• •••• ••••' : d;
    return Form(
      key: _formTarjeta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 155,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.darkPink, AppTheme.primaryPink],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(
                      Icons.memory_rounded,
                      color: Colors.white70,
                      size: 30,
                    ),
                    Text(
                      d.isEmpty ? '' : marca(d),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  visibles,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _nombreCtrl.text.isEmpty
                            ? 'NOMBRE DEL TITULAR'
                            : _nombreCtrl.text.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      _vigenciaCtrl.text.isEmpty ? 'MM/AA' : _vigenciaCtrl.text,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _numeroCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(16),
            ],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Número de tarjeta (16 dígitos)',
              prefixIcon: Icon(Icons.credit_card),
            ),
            validator: (v) {
              if (!RegExp(r'^\d{16}$').hasMatch((v ?? '').trim())) {
                return 'Ingresa exactamente 16 dígitos numéricos';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nombreCtrl,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Nombre del titular',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) => (v ?? '').trim().length < 3
                ? 'Escribe el nombre del titular'
                : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _vigenciaCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MesAnioInputFormatter()],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Vence (MM/AA)',
                    prefixIcon: Icon(Icons.event),
                  ),
                  validator: _validarVigencia,
                ),
              ),
              const SizedBox(width: 12),
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
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) {
                    if (!RegExp(r'^\d{3,4}$').hasMatch((v ?? '').trim())) {
                      return '3 o 4 dígitos';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
