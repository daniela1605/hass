import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../controllers/saldo_proveedor_controller.dart';
import '../models/gestopago_models.dart';
import '../repository/database_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/gestopago_ticket_dialog.dart';
import 'notificaciones_view.dart';

class HistorialView extends StatefulWidget {
  final int usuarioId;
  final bool esAdmin;

  const HistorialView({
    super.key,
    required this.usuarioId,
    this.esAdmin = false,
  });

  @override
  State<HistorialView> createState() => _HistorialViewState();
}

class _HistorialViewState extends State<HistorialView> {
  final _saldoCtrl = SaldoProveedorController.instance;
  List<Map<String, dynamic>> _historial = [];
  bool _isLoading = true;
  int _vistaSeleccionada = 0; // 0: Compras y Pagos, 1: Movimientos de Bolsa

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    await _saldoCtrl.init();
    final data = widget.esAdmin
        ? await DatabaseHelper.instance.obtenerTodoHistorial()
        : await DatabaseHelper.instance.obtenerHistorial(widget.usuarioId);
    if (mounted) {
      setState(() {
        _historial = data;
        _isLoading = false;
      });
    }
  }

  void _reabrirTicketOficial(Map<String, dynamic> h, List productos) {
    final primero = productos.isNotEmpty && productos.first is Map
        ? Map<String, dynamic>.from(productos.first as Map)
        : <String, dynamic>{};

    final folio = (h['transaction_id'] ?? primero['folio'] ?? 'GP-AUTH-000000')
        .toString();
    final idTx = (primero['id_tx'] ?? 'TX-GP-$folio').toString();
    final pin = primero['pin']?.toString();
    final ref = (primero['referencia'] ?? h['usuario_email'] ?? 'Cliente Mi Tiendita')
        .toString();
    final nombreProd =
        (primero['nombre'] ?? primero['nombre_product'] ?? 'Operación GestoPago')
            .toString();
    final legend = (primero['legend'] ??
            'Operación autorizada por GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V. Conserve su folio para cualquier aclaración.')
        .toString();
    final total = (h['total'] as num?)?.toDouble() ?? 0.0;
    final fecha =
        DateTime.tryParse(h['fecha'] as String? ?? '') ?? DateTime.now();

    final prodModelo = GestoPagoProducto(
      servicio: nombreProd.contains(' - ')
          ? nombreProd.split(' - ').first
          : 'GestoPago · Mi Tiendita',
      producto: nombreProd,
      idServicio: '1',
      idProducto: '1',
      idCatTipoServicio: pin != null ? '10' : '5',
      tipoFront: '1',
      hasDigitoVerificador: false,
      precio: total,
      showAyuda: false,
      tipoReferencia: 'a',
      legend: legend,
    );

    final resultado = ResultadoTransaccionGestoPago(
      aprobada: true,
      folioAutorizacion: folio,
      idTx: idTx,
      pinDigital: pin,
      producto: prodModelo,
      referenciaDestino: ref,
      monto: total,
      comisionGanada: SaldoProveedorController.comisionPorOperacion,
      metodoPago: (h['metodo_pago'] ?? 'saldo_proveedor').toString(),
      detalleMetodoPago: (h['detalle_pago'] ?? 'Autorizado GestoPago').toString(),
      saldoRestanteProveedor: _saldoCtrl.saldo,
      fecha: fecha,
      legendOficial: legend,
    );

    GestoPagoTicketDialog.mostrar(context, resultado);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softPinkBg,
      appBar: AppBar(
        title: Text(
          widget.esAdmin ? '📊 Historial General' : '📋 Historial y Folios',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: Icon(Icons.refresh_rounded, color: AppTheme.darkPink),
            onPressed: _cargar,
          ),
          const NotificacionesBoton(),
        ],
      ),
      body: Column(
        children: [
          // Selector segmentado entre Compras/Pagos y Movimientos de Bolsa
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: _botonSegmento(
                    index: 0,
                    icono: Icons.receipt_long_rounded,
                    titulo: 'Compras y Recargas (${_historial.length})',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _saldoCtrl,
                    builder: (_, _) => _botonSegmento(
                      index: 1,
                      icono: Icons.account_balance_wallet_rounded,
                      titulo: 'Movimientos Bolsa (${_saldoCtrl.movimientos.length})',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppTheme.darkPink))
                : _vistaSeleccionada == 0
                    ? _listaCompras()
                    : _listaMovimientosBolsa(),
          ),
        ],
      ),
    );
  }

  Widget _botonSegmento({
    required int index,
    required IconData icono,
    required String titulo,
  }) {
    final sel = _vistaSeleccionada == index;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _vistaSeleccionada = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: sel ? AppTheme.darkPink : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? AppTheme.darkPink : AppTheme.cardBorderPink,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icono,
              size: 16,
              color: sel ? Colors.white : AppTheme.darkPink,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: sel ? Colors.white : AppTheme.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listaCompras() {
    if (_historial.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 80, color: Colors.pink[200]),
            const SizedBox(height: 16),
            const Text(
              'No hay compras ni pagos aún',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _historial.length,
      itemBuilder: (_, i) {
        final h = _historial[i];
        final fecha =
            DateTime.tryParse(h['fecha'] as String? ?? '') ?? DateTime.now();
        final fechaStr = DateFormat('dd/MM/yyyy HH:mm').format(fecha);
        final total = (h['total'] as num).toDouble();
        List productos = [];
        try {
          productos = jsonDecode(h['productos_json'] as String? ?? '[]');
        } catch (_) {}

        final folio = (h['transaction_id'] ?? 'GP-AUTH').toString();

        return RepaintBoundary(
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: CircleAvatar(
                backgroundColor: AppTheme.cardBorderPink,
                child: Icon(Icons.receipt_long_rounded, color: AppTheme.darkPink),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      '\$${total.toStringAsFixed(2)} MXN',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkPink,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.softPinkBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.cardBorderPink),
                      ),
                      child: Text(
                        folio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkPink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    fechaStr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  if (widget.esAdmin && h['usuario_nombre'] != null)
                    Text(
                      '👤 ${h['usuario_nombre']} (${h['usuario_email']})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  if (h['detalle_pago'] != null)
                    Text(
                      '💳 ${h['detalle_pago']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: h['estado_pago'] == 'pendiente'
                            ? const Color(0xFFF57C00)
                            : AppTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Table(
                        columnWidths: const {
                          0: FlexColumnWidth(3),
                          1: FlexColumnWidth(1),
                          2: FlexColumnWidth(2),
                        },
                        children: [
                          TableRow(
                            decoration: BoxDecoration(
                              color: AppTheme.cardBorderPink.withValues(alpha: 0.5),
                            ),
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(6),
                                child: Text(
                                  'Concepto / Producto',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.all(6),
                                child: Text(
                                  'Cant.',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.all(6),
                                child: Text(
                                  'Subtotal',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ...productos.map((p) {
                            final precio = (p['precio'] as num).toDouble();
                            final cant = (p['cantidad'] as num).toInt();
                            final sub = precio * cant;
                            return TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    (p['nombre'] ?? p['nombre_product'] ?? '')
                                        .toString(),
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    '$cant',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    '\$${sub.toStringAsFixed(2)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.darkPink,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _reabrirTicketOficial(h, productos),
                          icon: Icon(
                            Icons.receipt_rounded,
                            size: 16,
                            color: AppTheme.darkPink,
                          ),
                          label: Text(
                            'Ver Comprobante Oficial ($folio)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkPink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _listaMovimientosBolsa() {
    return ListenableBuilder(
      listenable: _saldoCtrl,
      builder: (context, _) {
        final movs = _saldoCtrl.movimientos;
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: movs.length,
          itemBuilder: (_, i) {
            final m = movs[i];
            final esAbono = m.tipo == 'abono';
            final fechaStr = DateFormat('dd/MM/yyyy HH:mm').format(m.fecha);
            return RepaintBoundary(
              child: Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: esAbono
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFCE4EC),
                    child: Icon(
                      esAbono
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      color: esAbono
                          ? const Color(0xFF2E7D32)
                          : AppTheme.darkPink,
                    ),
                  ),
                  title: Text(
                    m.concepto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppTheme.textDark,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Folio: ${m.folio} · $fechaStr',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      Text(
                        'Saldo resultante: \$${m.saldoResultante.toStringAsFixed(2)} MXN',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${esAbono ? '+' : '-'}\$${m.monto.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          color: esAbono
                              ? const Color(0xFF2E7D32)
                              : AppTheme.darkPink,
                        ),
                      ),
                      if (m.comision > 0)
                        Text(
                          '+\$${m.comision.toStringAsFixed(2)} com.',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                    ],
                  ),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: m.folio));
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: AppTheme.darkPink,
                          content: Text('📋 Folio copiado: ${m.folio}'),
                        ),
                      );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
