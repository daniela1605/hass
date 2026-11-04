import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gestopago_models.dart';
import '../theme/app_theme.dart';

/// Controlador Singleton (`ChangeNotifier`) para gestionar la Bolsa de Saldo
/// con el Proveedor GestoPago (`GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V.`).
class SaldoProveedorController extends ChangeNotifier {
  SaldoProveedorController._();
  static final SaldoProveedorController instance = SaldoProveedorController._();

  static const double saldoInicialDemo = 2500.00;
  static const double comisionPorOperacion = 2.50;

  static const String _keySaldo = 'gp_bolsa_saldo_mxn';
  static const String _keyComision = 'gp_bolsa_comision_mxn';
  static const String _keyMovimientos = 'gp_bolsa_movimientos_json';

  double _saldo = saldoInicialDemo;
  double _comisionAcumulada = 0.0;
  List<MovimientoSaldo> _movimientos = [];
  bool _inicializado = false;

  double get saldo => _saldo;
  double get comisionAcumulada => _comisionAcumulada;
  List<MovimientoSaldo> get movimientos => List.unmodifiable(_movimientos);
  bool get tieneFondos => _saldo > 0;

  /// Carga el estado persistido en `SharedPreferences`.
  Future<void> init() async {
    if (_inicializado) return;
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_keySaldo)) {
      _saldo = saldoInicialDemo;
      await prefs.setDouble(_keySaldo, _saldo);
    } else {
      _saldo = prefs.getDouble(_keySaldo) ?? saldoInicialDemo;
    }
    _comisionAcumulada = prefs.getDouble(_keyComision) ?? 0.0;

    final rawList = prefs.getStringList(_keyMovimientos) ?? [];
    _movimientos = rawList
        .map((s) {
          try {
            return MovimientoSaldo.fromJson(
              jsonDecode(s) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<MovimientoSaldo>()
        .toList();

    if (_movimientos.isEmpty) {
      final movInicial = MovimientoSaldo(
        id: 'MOV-INIT',
        tipo: 'abono',
        concepto: 'Dotación inicial Bolsa Proveedor GestoPago (idDist=1, idEst=1)',
        monto: saldoInicialDemo,
        comision: 0.0,
        saldoResultante: _saldo,
        folio: 'GP-INIT-000001',
        metodoPago: 'Bolsa Inicial GestoPago',
        fecha: DateTime.now(),
      );
      _movimientos.insert(0, movInicial);
      await _guardarEstado();
    }

    _inicializado = true;
    notifyListeners();
  }

  /// Verifica estrictamente si `saldo > 0` y `saldo >= montoRequerido`.
  bool cuentaConFondosSuficientes(double montoRequerido) {
    if (montoRequerido <= 0) return false;
    return _saldo > 0 && _saldo >= montoRequerido;
  }

  /// Validación estricta ("Sí o sí debe disponer de dinero"):
  /// Si el saldo es insuficiente, bloquea la transacción, limpia y muestra un
  /// SnackBar sin encolar mensajes y lanza una alerta visual con acceso directo
  /// al modal **"Fondear / Recargar Saldo"**.
  bool validarFondosConAlerta(
    BuildContext context, {
    required double montoRequerido,
    required String conceptoOperacion,
    required VoidCallback onAbrirModalFondeo,
  }) {
    if (_saldo > 0 && _saldo >= montoRequerido) {
      return true;
    }

    final faltante = max(0.0, montoRequerido - _saldo);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFC62828),
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _saldo <= 0
                      ? 'Bolsa GestoPago en \$0.00 MXN. Fondea tu saldo para operar.'
                      : 'Saldo insuficiente en Bolsa (\$${_saldo.toStringAsFixed(2)}). Faltan \$${faltante.toStringAsFixed(2)} MXN.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'FONDEAR',
            textColor: const Color(0xFFFFEB3B),
            onPressed: onAbrirModalFondeo,
          ),
        ),
      );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                color: Color(0xFFC62828),
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Saldo Insuficiente con Proveedor',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB71C1C),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Para procesar "$conceptoOperacion", tu comercio debe disponer de saldo suficiente en la bolsa de GestoPago.',
              style: const TextStyle(fontSize: 13, color: AppTheme.textDark, height: 1.35),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.softPinkBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorderPink),
              ),
              child: Column(
                children: [
                  _filaResumenAlerta(
                    'Saldo actual disponible:',
                    '\$${_saldo.toStringAsFixed(2)} MXN',
                    const Color(0xFFC62828),
                  ),
                  const SizedBox(height: 6),
                  _filaResumenAlerta(
                    'Monto de la operación:',
                    '\$${montoRequerido.toStringAsFixed(2)} MXN',
                    AppTheme.textDark,
                  ),
                  const Divider(height: 16),
                  _filaResumenAlerta(
                    'Monto mínimo por fondear:',
                    '\$${faltante.toStringAsFixed(2)} MXN',
                    AppTheme.darkPink,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.darkPink,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onAbrirModalFondeo();
            },
            icon: const Icon(Icons.add_card_rounded, size: 18),
            label: const Text('Fondear / Recargar Saldo'),
          ),
        ],
      ),
    );

    return false;
  }

  Widget _filaResumenAlerta(String label, String valor, Color colorValor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          valor,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: colorValor,
          ),
        ),
      ],
    );
  }

  /// Fondeo / Abono (`recargarSaldo`):
  /// Permite abonar saldo mediante SPEI Directo, Tarjeta Bancaria o PayPal In-App,
  /// registrando el movimiento de abono con el folio retornado al aprobarse.
  Future<MovimientoSaldo> recargarSaldo({
    required double monto,
    required String metodoPago, // 'SPEI Directo' | 'Tarjeta Bancaria' | 'PayPal In-App'
    String? folioAprobacion,
  }) async {
    await init();
    final rnd = Random();
    final folio = folioAprobacion ??
        'GP-ABONO-${100000 + rnd.nextInt(899999)}';

    _saldo = double.parse((_saldo + monto).toStringAsFixed(2));

    final mov = MovimientoSaldo(
      id: 'MOV-${DateTime.now().millisecondsSinceEpoch}',
      tipo: 'abono',
      concepto: 'Abono a Bolsa GestoPago vía $metodoPago',
      monto: monto,
      comision: 0.0,
      saldoResultante: _saldo,
      folio: folio,
      metodoPago: metodoPago,
      fecha: DateTime.now(),
    );

    _movimientos.insert(0, mov);
    await _guardarEstado();
    notifyListeners();
    return mov;
  }

  /// Cargo (`descontarSaldo`):
  /// Descuenta el monto de la compra/pago, suma una comisión ganada por operación
  /// (`+$2.50 MXN` para el comercio) y guarda el movimiento con su concepto,
  /// fecha, saldo resultante y el folio oficial.
  Future<MovimientoSaldo> descontarSaldo({
    required double monto,
    required String concepto,
    required String folioOficial,
    required String metodoPago,
    double comision = comisionPorOperacion,
  }) async {
    await init();
    if (_saldo <= 0 || _saldo < monto) {
      throw StateError(
        'Fondos insuficientes en la Bolsa GestoPago (\$${_saldo.toStringAsFixed(2)} MXN).',
      );
    }

    _saldo = double.parse((_saldo - monto + comision).toStringAsFixed(2));
    _comisionAcumulada =
        double.parse((_comisionAcumulada + comision).toStringAsFixed(2));

    final mov = MovimientoSaldo(
      id: 'MOV-${DateTime.now().millisecondsSinceEpoch}',
      tipo: 'cargo',
      concepto: concepto,
      monto: monto,
      comision: comision,
      saldoResultante: _saldo,
      folio: folioOficial,
      metodoPago: metodoPago,
      fecha: DateTime.now(),
    );

    _movimientos.insert(0, mov);
    await _guardarEstado();
    notifyListeners();
    return mov;
  }

  /// Botón de simulación: "Reiniciar a $2,500.00"
  Future<void> reiniciarSaldoDemo() async {
    await init();
    _saldo = saldoInicialDemo;
    final mov = MovimientoSaldo(
      id: 'MOV-RESET-${DateTime.now().millisecondsSinceEpoch}',
      tipo: 'abono',
      concepto: 'Simulación: Reinicio de Bolsa a \$2,500.00 MXN',
      monto: saldoInicialDemo,
      comision: 0.0,
      saldoResultante: _saldo,
      folio: 'GP-SIM-RESET2500',
      metodoPago: 'Simulador Sandbox',
      fecha: DateTime.now(),
    );
    _movimientos.insert(0, mov);
    await _guardarEstado();
    notifyListeners();
  }

  /// Botón de simulación: "Simular Saldo $0.00" (para probar bloqueo por falta de fondos)
  Future<void> simularSaldoCero() async {
    await init();
    final anterior = _saldo;
    _saldo = 0.00;
    final mov = MovimientoSaldo(
      id: 'MOV-ZERO-${DateTime.now().millisecondsSinceEpoch}',
      tipo: 'simulacion',
      concepto: 'Simulación: Bolsa en \$0.00 MXN (Prueba de bloqueo)',
      monto: anterior,
      comision: 0.0,
      saldoResultante: 0.00,
      folio: 'GP-SIM-ZERO0000',
      metodoPago: 'Simulador Sandbox',
      fecha: DateTime.now(),
    );
    _movimientos.insert(0, mov);
    await _guardarEstado();
    notifyListeners();
  }

  Future<void> _guardarEstado() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySaldo, _saldo);
    await prefs.setDouble(_keyComision, _comisionAcumulada);
    final listJson = _movimientos
        .take(80)
        .map((m) => jsonEncode(m.toJson()))
        .toList();
    await prefs.setStringList(_keyMovimientos, listJson);
  }
}
