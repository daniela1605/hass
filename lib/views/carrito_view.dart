import '../models/gestopago_models.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../repository/database_helper.dart';
import '../services/mail_helper.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gestopago_ticket_dialog.dart';
import '../widgets/product_image.dart';
import 'pago_view.dart';

class CarritoView extends StatefulWidget {
  final int usuarioId;
  final String usuarioEmail;

  const CarritoView({super.key, required this.usuarioId, required this.usuarioEmail});

  @override
  State<CarritoView> createState() => _CarritoViewState();
}

class _CarritoViewState extends State<CarritoView> {
  List<Map<String, dynamic>> _cart = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _cargarCarrito();
  }

  Future<void> _cargarCarrito() async {
    final items = await DatabaseHelper.instance.obtenerCarrito(widget.usuarioId);
    if (mounted) setState(() => _cart = items);
  }

  double get _total => _cart.fold(0.0, (sum, item) =>
    sum + ((item['precio'] as num).toDouble() * (item['cantidad'] as int)));

  Future<void> _eliminarItem(int id) async {
    await DatabaseHelper.instance.eliminarDelCarrito(id);
    await _cargarCarrito();
  }

  /// Pasarela de pago: El usuario selecciona su método de pago preferido
  Future<void> _finalizarCompra() async {
    if (_cart.isEmpty) return;

    final pago = await Navigator.push<ResultadoPago>(
      context,
      MaterialPageRoute(
          builder: (_) => PagoView(total: _total, emailUsuario: widget.usuarioEmail)),
    );
    if (pago == null || !mounted) return; // el usuario canceló

    // El Folio Oficial proviene exclusivamente de la autorización del pago
    final folioRemision = pago.referencia;
    final fechaCompra = DateTime.now();

    setState(() => _isLoading = true);

    try {
      // 1. Guardar en SQLite
      final productosJson = jsonEncode(_cart);
      await DatabaseHelper.instance.guardarCompra(
        widget.usuarioId,
        productosJson,
        _total,
        folioRemision,
        metodoPago: pago.metodo,
        detallePago: pago.resumen,
        estadoPago: pago.estado,
      );

      // 1b. Registrar la compra para las recomendaciones
      for (final c in _cart) {
        await DatabaseHelper.instance
            .registrarInteraccion(widget.usuarioId, c['producto_id'] as int, 'compra');
      }

      // 2. Enviar Nota de Remisión al correo del comprador
      final totalCompra = _total;
      final items = _cart.map((c) => {
        'nombre_product': c['nombre'],
        'precio': (c['precio'] as num).toDouble(),
        'cantidad': c['cantidad'] as int,
      }).toList();

      try {
        await MailHelper.sendPurchaseSummaryEmail(
          widget.usuarioEmail,
          items,
          totalCompra,
          folioRemision,
          fechaCompra,
          null,
          pago.resumen,
        );
      } catch (e) {
        debugPrint('Error enviando nota de remisión: $e');
      }

      // 2b. Notificación en tiempo real
      await NotificationService.instance.notificar(
        widget.usuarioId,
        pago.pendiente ? '⏳ Pedido registrado (pago pendiente)' : '🎉 ¡Pedido confirmado!',
        'Folio $folioRemision · Total \$${totalCompra.toStringAsFixed(2)} MXN · ${ResultadoPago.etiqueta(pago.metodo)}',
        tipo: 'compras',
      );

      // 3. Limpiar carrito de compras
      await DatabaseHelper.instance.limpiarCarrito(widget.usuarioId);

      setState(() {
        _cart = [];
        _isLoading = false;
      });
      if (!mounted) return;

      // 4. Mostrar Comprobante Oficial GestoPagoTicketDialog (con autorización oficial simulada)
      final ticketMostrar = pago.ticketGestoPago ??
          ResultadoTransaccionGestoPago(
            aprobada: true,
            folioAutorizacion: folioRemision,
            idTx: '291437188',
            producto: const GestoPagoProducto(
              servicio: 'GestoPago · Mi Tiendita',
              producto: 'Compra Carrito de Tienda',
              idServicio: '19',
              idProducto: '1999',
              idCatTipoServicio: '19',
              tipoFront: '2',
              hasDigitoVerificador: false,
              precio: 0.0,
              showAyuda: false,
              tipoReferencia: 'a',
              legend:
                  'Operación autorizada por GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V. Conserve su folio para cualquier aclaración.',
            ),
            referenciaDestino: widget.usuarioEmail,
            monto: totalCompra,
            comisionGanada: 0.70,
            metodoPago: pago.metodo,
            detalleMetodoPago: pago.resumen,
            saldoRestanteProveedor: 157731.83,
            fecha: fechaCompra,
            legendOficial:
                'Operación realizada con éxito. Autorización oficial $folioRemision (ID TX: 291437188) emitida por GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V.',
            modoRespaldo: true,
          );

      if (mounted) {
        await GestoPagoTicketDialog.mostrar(context, ticketMostrar);
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar compra: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softPinkBg,
      appBar: AppBar(
        title: const Text('🛒 Mi Carrito de Compras'),
      ),
      body: _cart.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.pink[200]),
                  const SizedBox(height: 16),
                  const Text('Tu carrito está vacío', style: TextStyle(color: AppTheme.textMuted, fontSize: 18)),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _cart.length,
                    itemBuilder: (_, i) {
                      final item = _cart[i];
                      final subtotal = (item['precio'] as num).toDouble() * (item['cantidad'] as int);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: ProductImage(
                            imageSource: item['imagen']?.toString(),
                            width: 56,
                            height: 56,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          title: Text(
                            item['nombre'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                          ),
                          subtitle: Text(
                            '\$${(item['precio'] as num).toDouble().toStringAsFixed(2)} × ${item['cantidad']} = \$${subtotal.toStringAsFixed(2)} MXN',
                            style: TextStyle(color: AppTheme.darkPink, fontWeight: FontWeight.w600),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_rounded, color: Colors.red),
                            onPressed: () => _eliminarItem(item['id'] as int),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Panel de total y botón de compra
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.cardBorderPink.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, -4),
                      ),
                    ],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total a pagar:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                          Text(
                            '\$${_total.toStringAsFixed(2)} MXN',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.darkPink),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _finalizarCompra,
                          icon: _isLoading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.shopping_bag_rounded),
                          label: Text(
                            _isLoading ? 'Generando Nota de Remisión...' : 'Continuar al pago 💳',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
