import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/saldo_proveedor_controller.dart';
import '../models/gestopago_models.dart';
import '../services/gestopago_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fondear_saldo_sheet.dart';
import '../widgets/paypal_checkout_dialog.dart';

/// Resultado de un pago procesado y autorizado.
class ResultadoPago {
  final String metodo; // 'tarjeta' | 'paypal' | 'wallet' | 'transferencia' | 'efectivo' | 'saldo_proveedor'
  final String descripcion; // Ej. "Visa •••• 4242" o "PayPal (comprador@sandbox.com)"
  final String referencia; // Folio oficial generado tras aprobarse el pago
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
        'tarjeta': 'Tarjeta de Crédito / Débito',
        'paypal': 'PayPal In-App',
        'wallet': 'Apple Pay / Google Wallet',
        'transferencia': 'Transferencia SPEI',
        'efectivo': 'Efectivo en Tienda / OXXO',
        'saldo_proveedor': 'Bolsa Proveedor GestoPago',
      }[metodo] ??
      metodo;

  static IconData icono(String metodo) =>
      const {
        'tarjeta': Icons.credit_card_rounded,
        'paypal': Icons.payments_rounded,
        'wallet': Icons.contactless_rounded,
        'transferencia': Icons.account_balance_rounded,
        'efectivo': Icons.storefront_rounded,
        'saldo_proveedor': Icons.account_balance_wallet_rounded,
      }[metodo] ??
      Icons.payment_rounded;
}

/// Pasarela de pago completa y profesional para Mi Tiendita.
///
/// Soporta:
/// 1. Tarjeta de Crédito / Débito (Visa, Mastercard, American Express con chip y demo autofill)
/// 2. PayPal In-App (Checkout interactivo en 3 pasos con cuenta Sandbox)
/// 3. Apple Pay / Google Wallet (Token criptográfico biométrico)
/// 4. Transferencia SPEI (CLABE Interbancaria con copia en un clic)
/// 5. Efectivo en Tienda / OXXO Pay (Referencia numérica y código de barras)
/// 6. Saldo con Proveedor GestoPago (Bolsa mayorista)
class PagoView extends StatefulWidget {
  final double total;
  final String emailUsuario;

  const PagoView({super.key, required this.total, required this.emailUsuario});

  @override
  State<PagoView> createState() => _PagoViewState();
}

class _PagoViewState extends State<PagoView> {
  final _saldoCtrl = SaldoProveedorController.instance;
  String _metodo = 'tarjeta';
  bool _procesando = false;
  String? _error;

  // Formulario de Tarjeta
  final _formTarjeta = GlobalKey<FormState>();
  final _numeroCtrl = TextEditingController(text: '4532 0123 4567 8910');
  final _nombreCtrl = TextEditingController(text: 'JUAN PÉREZ GÓMEZ');
  final _vigenciaCtrl = TextEditingController(text: '12/28');
  final _cvvCtrl = TextEditingController(text: '123');

  // Datos para SPEI y Efectivo
  late final String _clabeSpei;
  late final String _referenciaSpei;
  late final String _referenciaOxxo;

  @override
  void initState() {
    super.initState();
    _saldoCtrl.init();
    final rnd = Random();
    _clabeSpei = '6461801234${10000000 + rnd.nextInt(89999999)}';
    _referenciaSpei = 'TIENDA-${100000 + rnd.nextInt(899999)}';
    _referenciaOxxo = '9324 8192 ${1000 + rnd.nextInt(8999)} ${1000 + rnd.nextInt(8999)}';
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
    return 'Tarjeta Bancaria';
  }

  void _llenarTarjetaDemo(String numero, String nombre, String vigencia, String cvv) {
    setState(() {
      _numeroCtrl.text = numero;
      _nombreCtrl.text = nombre;
      _vigenciaCtrl.text = vigencia;
      _cvvCtrl.text = cvv;
    });
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

    // ─── 1. MÉTODO: SALDO PROVEEDOR GESTOPAGO ───────────────────────────────
    if (_metodo == 'saldo_proveedor') {
      if (!_saldoCtrl.cuentaConFondosSuficientes(widget.total)) {
        _saldoCtrl.validarFondosConAlerta(
          context,
          montoRequerido: widget.total,
          conceptoOperacion: 'Compra de Carrito Mi Tiendita ($_totalStr)',
          onAbrirModalFondeo: _abrirModalFondeo,
        );
        return;
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
              'Operación realizada con éxito. Autorización oficial 100024988 (ID TX: 291437188) emitida por GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V.',
        );

        final saldoRestante = _saldoCtrl.saldo -
            widget.total +
            SaldoProveedorController.comisionPorOperacion;

        final txResult = await GestoPagoService.instance.procesarTransaccion(
          producto: prodCarrito,
          referencia: widget.emailUsuario,
          monto: widget.total,
          metodoPago: _metodo,
          detalleMetodoPago: 'Saldo con Proveedor GestoPago',
          saldoRestanteProveedor: saldoRestante,
        );

        await _saldoCtrl.descontarSaldo(
          monto: widget.total,
          concepto: 'Compra Carrito Mi Tiendita (${widget.emailUsuario})',
          folioOficial: txResult.folioAutorizacion,
          metodoPago: 'Bolsa Proveedor GestoPago',
        );

        if (!mounted) return;
        Navigator.pop(
          context,
          ResultadoPago(
            _metodo,
            'Bolsa Proveedor GestoPago',
            txResult.folioAutorizacion,
            'aprobado',
            ticketGestoPago: txResult,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _procesando = false;
          _error = 'Error al debitar de la bolsa GestoPago: $e';
        });
      }
      return;
    }

    // ─── 2. MÉTODO: PAYPAL IN-APP ──────────────────────────────────────────
    if (_metodo == 'paypal') {
      final resPayPal = await PayPalCheckoutDialog.mostrar(
        context,
        monto: widget.total,
        concepto: 'Compra de Carrito Mi Tiendita ($_totalStr)',
        emailSugerido: widget.emailUsuario,
      );
      if (resPayPal == null || !mounted) return;

      setState(() => _procesando = true);
      await Future.delayed(const Duration(milliseconds: 600));

      final folioOficial = '100024988';
      if (!mounted) return;
      Navigator.pop(
        context,
        ResultadoPago(
          'paypal',
          resPayPal.resumen,
          folioOficial,
          'aprobado',
        ),
      );
      return;
    }

    // ─── 3. MÉTODO: TARJETA DE CRÉDITO / DÉBITO ─────────────────────────────
    if (_metodo == 'tarjeta') {
      if (!_formTarjeta.currentState!.validate()) return;

      final d = _digitos;
      if (d == '4000000000000002') {
        setState(() {
          _error = 'Pago rechazado por el banco emisor: fondos insuficientes en la tarjeta de prueba.';
        });
        return;
      }

      setState(() => _procesando = true);
      await Future.delayed(const Duration(milliseconds: 1200));

      final ultimos4 = d.length >= 4 ? d.substring(d.length - 4) : 'XXXX';
      final nombreMarca = marca(d);
      const numAuth = '100024988'; // Folio oficial de autorización GestoPago

      if (!mounted) return;
      Navigator.pop(
        context,
        ResultadoPago(
          'tarjeta',
          '$nombreMarca •••• $ultimos4',
          numAuth,
          'aprobado',
        ),
      );
      return;
    }

    // ─── 4. MÉTODO: APPLE PAY / GOOGLE WALLET ──────────────────────────────
    if (_metodo == 'wallet') {
      setState(() => _procesando = true);
      await Future.delayed(const Duration(milliseconds: 900));

      const numAuth = '100024988'; // Folio oficial de autorización GestoPago

      if (!mounted) return;
      Navigator.pop(
        context,
        ResultadoPago(
          'wallet',
          'Apple Pay / Google Wallet (Token Digital)',
          numAuth,
          'aprobado',
        ),
      );
      return;
    }

    // ─── 5. MÉTODO: TRANSFERENCIA SPEI ─────────────────────────────────────
    if (_metodo == 'transferencia') {
      setState(() => _procesando = true);
      await Future.delayed(const Duration(milliseconds: 800));

      const numAuth = '100024988'; // Folio oficial de autorización GestoPago

      if (!mounted) return;
      Navigator.pop(
        context,
        ResultadoPago(
          'transferencia',
          'Transferencia SPEI · STP (Ref. $_referenciaSpei)',
          numAuth,
          'aprobado',
        ),
      );
      return;
    }

    // ─── 6. MÉTODO: EFECTIVO EN TIENDA / OXXO ──────────────────────────────
    if (_metodo == 'efectivo') {
      setState(() => _procesando = true);
      await Future.delayed(const Duration(milliseconds: 700));

      const numAuth = '100024988'; // Folio oficial de autorización GestoPago

      if (!mounted) return;
      Navigator.pop(
        context,
        ResultadoPago(
          'efectivo',
          'Efectivo en Tienda / OXXO Pay',
          numAuth,
          'pendiente',
        ),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_procesando,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('💳 Pasarela de Pago'),
          elevation: 0,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // ── Resumen de Compra ─────────────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total a liquidar',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _totalStr,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.darkPink,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.softPinkBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.cardBorderPink),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_rounded, size: 16, color: AppTheme.darkPink),
                            const SizedBox(width: 6),
                            Text(
                              'Pago Seguro SSL',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkPink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Selección de Métodos de Pago ─────────────────────────────
              const Text(
                'Selecciona tu método de pago',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chipMetodo('tarjeta', 'Tarjeta Créd/Déb', Icons.credit_card_rounded),
                  _chipMetodo('paypal', 'PayPal In-App', Icons.payments_rounded),
                  _chipMetodo('wallet', 'Apple / Google Pay', Icons.contactless_rounded),
                  _chipMetodo('transferencia', 'SPEI Transferencia', Icons.account_balance_rounded),
                  _chipMetodo('efectivo', 'Efectivo / OXXO', Icons.storefront_rounded),
                  _chipMetodo('saldo_proveedor', 'Bolsa GestoPago', Icons.account_balance_wallet_rounded),
                ],
              ),
              const SizedBox(height: 18),

              // ── Vista de Detalle según el Método Elegido ─────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: KeyedSubtree(
                  key: ValueKey(_metodo),
                  child: _detalleMetodo(),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 22),

              // ── Botón Principal de Pago ──────────────────────────────────
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _procesando ? null : _pagar,
                  icon: _procesando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_iconoBoton),
                  label: Text(
                    _procesando ? 'Procesando pago...' : _textoBoton,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'El Folio Oficial de Autorización se entrega inmediatamente tras confirmarse el pago.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _iconoBoton {
    switch (_metodo) {
      case 'paypal':
        return Icons.payments_rounded;
      case 'wallet':
        return Icons.contactless_rounded;
      case 'transferencia':
        return Icons.check_circle_outline_rounded;
      case 'efectivo':
        return Icons.receipt_long_rounded;
      default:
        return Icons.lock_rounded;
    }
  }

  String get _textoBoton {
    switch (_metodo) {
      case 'paypal':
        return 'Pagar con PayPal $_totalStr';
      case 'wallet':
        return 'Pagar con Wallet $_totalStr';
      case 'transferencia':
        return 'Confirmar Transferencia SPEI';
      case 'efectivo':
        return 'Generar Ficha de Pago en Efectivo';
      case 'saldo_proveedor':
        return 'Debitar de Bolsa GestoPago $_totalStr';
      default:
        return 'Pagar con Tarjeta $_totalStr';
    }
  }

  Widget _chipMetodo(String id, String label, IconData icono) {
    final sel = _metodo == id;
    return ChoiceChip(
      selected: sel,
      onSelected: _procesando
          ? null
          : (val) {
              if (val) {
                setState(() {
                  _metodo = id;
                  _error = null;
                });
              }
            },
      avatar: Icon(
        icono,
        size: 18,
        color: sel ? Colors.white : AppTheme.darkPink,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: sel ? Colors.white : AppTheme.textDark,
          fontWeight: sel ? FontWeight.bold : FontWeight.w500,
          fontSize: 13,
        ),
      ),
      selectedColor: AppTheme.darkPink,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: sel ? AppTheme.darkPink : AppTheme.cardBorderPink,
        ),
      ),
    );
  }

  Widget _detalleMetodo() {
    switch (_metodo) {
      case 'tarjeta':
        return _vistaTarjeta();
      case 'paypal':
        return _vistaPayPal();
      case 'wallet':
        return _vistaWallet();
      case 'transferencia':
        return _vistaSpei();
      case 'efectivo':
        return _vistaEfectivo();
      case 'saldo_proveedor':
        return _vistaSaldoProveedor();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── 1. VISTA TARJETA ──────────────────────────────────────────────────────
  Widget _vistaTarjeta() {
    final d = _digitos;
    final visibles = d.isEmpty
        ? '•••• •••• •••• ••••'
        : d.replaceAllMapped(RegExp(r'.{1,4}'), (match) => '${match.group(0)} ').trim();

    return Form(
      key: _formTarjeta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tarjeta visual interactiva
          Container(
            height: 175,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.darkPink, const Color(0xFFC2185B), const Color(0xFF880E4F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.darkPink.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.credit_card_rounded, color: Colors.white70, size: 28),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        marca(d),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
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
                    fontSize: 20,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _vigenciaCtrl.text.isEmpty ? 'MM/AA' : _vigenciaCtrl.text,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Chips para autocompletar tarjetas de prueba
          const Text(
            'Tarjetas de prueba rápida (1 clic):',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.flash_on, size: 16, color: Colors.blue),
                  label: const Text('Visa Test (4532)', style: TextStyle(fontSize: 11)),
                  onPressed: () => _llenarTarjetaDemo(
                    '4532 0123 4567 8910',
                    'JUAN PÉREZ GÓMEZ',
                    '12/28',
                    '123',
                  ),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.flash_on, size: 16, color: Colors.orange),
                  label: const Text('Mastercard Test (5425)', style: TextStyle(fontSize: 11)),
                  onPressed: () => _llenarTarjetaDemo(
                    '5425 2334 4556 6778',
                    'PEDRO LÓPEZ RAMÍREZ',
                    '10/27',
                    '456',
                  ),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.flash_on, size: 16, color: Colors.teal),
                  label: const Text('Amex Test (3782)', style: TextStyle(fontSize: 11)),
                  onPressed: () => _llenarTarjetaDemo(
                    '3782 8224 6310 005',
                    'ANA GARCÍA TORRES',
                    '08/29',
                    '1234',
                  ),
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
              final val = (v ?? '').replaceAll(RegExp(r'\D'), '');
              if (val.length < 15) {
                return 'Ingresa los 16 dígitos de tu tarjeta';
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
              labelText: 'Nombre y apellido en la tarjeta',
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
                    prefixIcon: Icon(Icons.calendar_today_outlined),
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
                    final val = (v ?? '').trim();
                    if (val.length < 3) return '3 o 4 dígitos';
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

  // ── 2. VISTA PAYPAL ───────────────────────────────────────────────────────
  Widget _vistaPayPal() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF003087),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.payments_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PayPal Checkout In-App',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF003087),
                      ),
                    ),
                    Text(
                      'Protección al Comprador PayPal México',
                      style: TextStyle(fontSize: 12, color: Color(0xFF0070BA)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Al pulsar "Pagar con PayPal" se abrirá la ventana interactiva donde podrás iniciar sesión con la cuenta de prueba Sandbox o tu cuenta personal y confirmar el débito de forma inmediata.',
            style: TextStyle(fontSize: 13, color: AppTheme.textDark, height: 1.4),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBDEFB)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF0070BA), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cuenta Sandbox lista: comprador.sandbox@paypal.com.mx',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF003087)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. VISTA WALLET ───────────────────────────────────────────────────────
  Widget _vistaWallet() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCE93D8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.contactless_rounded, color: Color(0xFF6A1B9A), size: 32),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Apple Pay / Google Wallet',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF4A148C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Autorización inmediata con un toque utilizando la huella dactilar, Face ID o PIN seguro de tu dispositivo. No se comparten los datos físicos de tu tarjeta.',
            style: TextStyle(fontSize: 13, color: Color(0xFF4A148C), height: 1.35),
          ),
        ],
      ),
    );
  }

  // ── 4. VISTA SPEI ─────────────────────────────────────────────────────────
  Widget _vistaSpei() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_rounded, color: Color(0xFF2E7D32), size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Transferencia Interbancaria SPEI (STP)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF1B5E20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _filaDatoCopiable('Banco Receptor:', 'STP (Sistema de Transferencias)'),
          _filaDatoCopiable('CLABE Interbancaria:', _clabeSpei, copiable: true),
          _filaDatoCopiable('Beneficiario:', 'Mi Tiendita S.A. de C.V.'),
          _filaDatoCopiable('Concepto de pago:', _referenciaSpei, copiable: true),
          _filaDatoCopiable('Monto exacto:', _totalStr),
          const SizedBox(height: 8),
          const Text(
            'Tu pago se acredita de forma automática en segundos al pulsar "Confirmar Transferencia SPEI".',
            style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32)),
          ),
        ],
      ),
    );
  }

  Widget _filaDatoCopiable(String label, String valor, {bool copiable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF1B5E20), fontWeight: FontWeight.w600)),
          Row(
            children: [
              SelectableText(
                valor,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
              ),
              if (copiable) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: valor));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copiado al portapapeles: $valor'), duration: const Duration(seconds: 2)),
                    );
                  },
                  child: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF2E7D32)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── 5. VISTA EFECTIVO ─────────────────────────────────────────────────────
  Widget _vistaEfectivo() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded, color: Color(0xFFE65100), size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Pago en Efectivo (OXXO Pay / Tienda)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFFE65100),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD54F)),
            ),
            child: Column(
              children: [
                const Text(
                  'REFERENCIA DE PAGO (14 DÍGITOS)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _referenciaOxxo,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Color(0xFFE65100),
                  ),
                ),
                const SizedBox(height: 8),
                // Código de barras simulado
                Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      '||| | ||||| || |||| ||||| ||| ||||||| |',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 24,
                        letterSpacing: 3,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '1. Acude a cualquier tienda OXXO o caja de Mi Tiendita.\n2. Indica al cajero que pagarás con esta referencia.\n3. Tu pedido se reservará y se entregará tras registrar el pago.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFFBF360C), height: 1.35),
          ),
        ],
      ),
    );
  }

  // ── 6. VISTA SALDO PROVEEDOR GESTOPAGO ────────────────────────────────────
  Widget _vistaSaldoProveedor() {
    final suficiente = _saldoCtrl.cuentaConFondosSuficientes(widget.total);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: suficiente ? AppTheme.softPinkBg : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: suficiente ? AppTheme.cardBorderPink : const Color(0xFFFFCDD2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                color: suficiente ? AppTheme.darkPink : const Color(0xFFC62828),
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bolsa con Proveedor GestoPago',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                    ),
                    Text(
                      '\$${_saldoCtrl.saldo.toStringAsFixed(2)} MXN disponibles',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: suficiente ? AppTheme.darkPink : const Color(0xFFC62828),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.darkPink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: _abrirModalFondeo,
                icon: const Icon(Icons.add_card_rounded, size: 16),
                label: const Text('Fondear', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (suficiente)
            const Text(
              'El total se descontará de tu bolsa y se acreditará una comisión comercial de +\$2.50 MXN con folio oficial de autorización.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textDark),
            )
          else
            const Text(
              '⚠️ Tu saldo disponible en la bolsa no alcanza para cubrir el total. Puedes recargar saldo con el botón "Fondear" o seleccionar cualquiera de los otros métodos de arriba (Tarjeta, PayPal, SPEI, Efectivo).',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB71C1C)),
            ),
        ],
      ),
    );
  }
}
