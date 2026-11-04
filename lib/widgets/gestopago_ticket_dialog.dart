import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/gestopago_models.dart';
import '../theme/app_theme.dart';

/// Comprobante Oficial (`GestoPagoTicketDialog`) post-pago.
/// Muestra únicamente después de autorizarse la transacción el Folio Oficial
/// retornado por el proveedor, junto con servicio, referencia/teléfono, monto,
/// comisión ganada, método de pago, saldo restante, PIN digital (si aplica)
/// y la leyenda oficial del XML (`legend`).
class GestoPagoTicketDialog extends StatelessWidget {
  final ResultadoTransaccionGestoPago resultado;

  const GestoPagoTicketDialog({super.key, required this.resultado});

  static Future<void> mostrar(
    BuildContext context,
    ResultadoTransaccionGestoPago resultado,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GestoPagoTicketDialog(resultado: resultado),
    );
  }

  void _copiarTexto(BuildContext context, String valor, String etiqueta) {
    Clipboard.setData(ClipboardData(text: valor));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.darkPink,
          duration: const Duration(seconds: 2),
          content: Text('📋 $etiqueta copiado al portapapeles: $valor'),
        ),
      );
  }

  void _compartirComprobante() {
    final fechaStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(resultado.fecha);
    final buffer = StringBuffer()
      ..writeln('🧾 COMPROBANTE OFICIAL GESTOPAGO')
      ..writeln('GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V.')
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln('✅ ESTADO: TRANSACCIÓN APROBADA')
      ..writeln('🔐 FOLIO AUTORIZACIÓN: ${resultado.folioAutorizacion}')
      ..writeln('🆔 ID TRANSACCIÓN: ${resultado.idTx}')
      ..writeln('📦 SERVICIO: ${resultado.producto.servicio}')
      ..writeln('🏷️ PRODUCTO: ${resultado.producto.producto}')
      ..writeln('🔢 REFERENCIA / DESTINO: ${resultado.referenciaDestino}')
      ..writeln('💵 MONTO PAGADO: \$${resultado.monto.toStringAsFixed(2)} MXN')
      ..writeln('💳 MÉTODO DE PAGO: ${resultado.detalleMetodoPago}')
      ..writeln('📅 FECHA Y HORA: $fechaStr');

    if (resultado.pinDigital != null && resultado.pinDigital!.isNotEmpty) {
      buffer.writeln('🎁 PIN DIGITAL DE CANJE: ${resultado.pinDigital}');
    }
    buffer
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln(resultado.legendOficial);

    SharePlus.instance.share(
      ShareParams(
        text: buffer.toString(),
        subject: 'Comprobante GestoPago ${resultado.folioAutorizacion}',
      ),
    );
  }

  String get _etiquetaReferencia {
    switch (resultado.producto.categoria) {
      case CategoriaGestoPago.recargas:
        return 'Número Telefónico';
      case CategoriaGestoPago.pines:
        return 'Correo Destino PIN';
      case CategoriaGestoPago.servicios:
      case CategoriaGestoPago.otros:
        return 'Referencia / Contrato';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fechaStr = DateFormat('dd/MM/yyyy · HH:mm:ss').format(resultado.fecha);
    final tienePin =
        resultado.pinDigital != null && resultado.pinDigital!.trim().isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Encabezado de Ticket Oficial ─────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.darkPink, resultado.producto.colorMarca],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'COMPROBANTE OFICIAL DE OPERACIÓN',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V.',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '\$${resultado.monto.toStringAsFixed(2)} MXN',
                          style: TextStyle(
                            color: AppTheme.darkPink,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Borde perforado estilo recibo ────────────────────────────
                SizedBox(
                  height: 16,
                  child: Row(
                    children: List.generate(
                      22,
                      (i) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 1.5,
                          color: i.isEven
                              ? AppTheme.cardBorderPink
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Caja de Folio Oficial de Autorización ──────────────
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.softPinkBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.cardBorderPink,
                            width: 1.4,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.workspace_premium_rounded,
                              color: AppTheme.darkPink,
                              size: 26,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'FOLIO DE AUTORIZACIÓN PROVEEDOR',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textMuted,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    resultado.folioAutorizacion,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.darkPink,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  Text(
                                    'ID Tx: ${resultado.idTx}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copiar Folio',
                              onPressed: () => _copiarTexto(
                                context,
                                resultado.folioAutorizacion,
                                'Folio de Autorización',
                              ),
                              icon: Icon(
                                Icons.copy_rounded,
                                color: AppTheme.darkPink,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Caja de PIN Digital (solo para PINes) ─────────────
                      if (tienePin) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.vpn_key_rounded,
                                    color: Color(0xFFFFD54F),
                                    size: 18,
                                  ),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'PIN DIGITAL DE CANJE ENTREGADO',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Color(0xFFFFD54F),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      resultado.pinDigital!,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFD54F),
                                      foregroundColor: const Color(0xFF1A237E),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () => _copiarTexto(
                                      context,
                                      resultado.pinDigital!,
                                      'PIN Digital',
                                    ),
                                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                                    label: const Text(
                                      'Copiar PIN',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // ── Detalles desglosados de la operación ───────────────
                      _filaRecibo('Servicio:', resultado.producto.servicio, negrita: true),
                      _filaRecibo('Producto:', resultado.producto.producto),
                      _filaRecibo(
                        'Categoría XML:',
                        '${resultado.producto.subcategoria} (Cat. ${resultado.producto.idCatTipoServicio})',
                      ),
                      _filaRecibo(_etiquetaReferencia, resultado.referenciaDestino, negrita: true),
                      _filaRecibo('Método de Pago:', resultado.detalleMetodoPago),
                      _filaRecibo(
                        'Comisión Ganada Comercio:',
                        '+\$${resultado.comisionGanada.toStringAsFixed(2)} MXN',
                        colorValor: const Color(0xFF2E7D32),
                        negrita: true,
                      ),
                      _filaRecibo(
                        'Saldo Restante Bolsa:',
                        '\$${resultado.saldoRestanteProveedor.toStringAsFixed(2)} MXN',
                        negrita: true,
                      ),
                      _filaRecibo('Fecha y Hora:', fechaStr),
                      _filaRecibo('Comercio:', 'idDistribuidor=1 · idEstablecimiento=1'),

                      const SizedBox(height: 12),

                      // ── Leyenda Oficial del XML (`legend`) ─────────────────
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.gavel_rounded,
                                  size: 14,
                                  color: AppTheme.textMuted,
                                ),
                                SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    'Leyenda Oficial Proveedor (<legend> XML):',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              resultado.legendOficial,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textDark,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── Botones de Acción ──────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.darkPink,
                                side: BorderSide(color: AppTheme.darkPink),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _compartirComprobante,
                              icon: const Icon(Icons.share_rounded, size: 18),
                              label: const Text(
                                'Compartir',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.darkPink,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                              label: const Text(
                                'Aceptar y Cerrar',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaRecibo(
    String etiqueta,
    String valor, {
    bool negrita = false,
    Color? colorValor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              valor,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: negrita ? FontWeight.bold : FontWeight.w500,
                color: colorValor ?? AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
