import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/gestopago_models.dart';
import '../theme/app_theme.dart';
import '../services/mail_helper.dart';
import '../services/app_settings.dart';

/// Comprobante Oficial (`GestoPagoTicketDialog`) post-pago.
/// Permite compartir el comprobante en formato de IMAGEN PNG (en lugar de solo texto)
/// capturando el renderizado exacto del ticket con alta resolución.
class GestoPagoTicketDialog extends StatefulWidget {
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

  @override
  State<GestoPagoTicketDialog> createState() => _GestoPagoTicketDialogState();
}

class _GestoPagoTicketDialogState extends State<GestoPagoTicketDialog> {
  final GlobalKey _ticketKey = GlobalKey();
  bool _generandoImagen = false;
  bool _enviandoCorreo = false;

  Future<void> _enviarTicketPorCorreo() async {
    if (_enviandoCorreo) return;
    setState(() => _enviandoCorreo = true);
    final destino = widget.resultado.referenciaDestino.contains('@')
        ? widget.resultado.referenciaDestino
        : AppSettings.instance.smtpUsuario;

    final exito = await MailHelper.sendPurchaseSummaryEmail(
      destino,
      [
        {
          'nombre_product': widget.resultado.producto.producto,
          'precio': widget.resultado.monto,
          'cantidad': 1,
        }
      ],
      widget.resultado.monto,
      widget.resultado.folioAutorizacion,
      widget.resultado.fecha,
      null,
      widget.resultado.detalleMetodoPago,
    );

    if (mounted) {
      setState(() => _enviandoCorreo = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: exito ? AppTheme.darkPink : Colors.orange[800],
            duration: const Duration(seconds: 4),
            content: Text(
              exito
                  ? '📧 Comprobante oficial enviado exitosamente a $destino'
                  : '⚠️ No se pudo enviar el correo a $destino (revisa tu configuración en Ajustes).',
            ),
            action: SnackBarAction(
              label: 'Abrir Gmail',
              textColor: Colors.white,
              onPressed: () async {
                final asunto = Uri.encodeComponent(
                    '🧾 Comprobante Oficial GestoPago - Folio ${widget.resultado.folioAutorizacion}');
                final cuerpo = Uri.encodeComponent(
                    'Comprobante Oficial GestoPago\n'
                    'Folio Autorización: ${widget.resultado.folioAutorizacion}\n'
                    'ID Transacción: ${widget.resultado.idTx}\n'
                    'Monto: \$${widget.resultado.monto.toStringAsFixed(2)} MXN\n'
                    'Método: ${widget.resultado.detalleMetodoPago}\n'
                    'Fecha: ${widget.resultado.fecha}\n\n'
                    '${widget.resultado.legendOficial}');
                final url = Uri.parse(
                    'https://mail.google.com/mail/?view=cm&fs=1&to=$destino&su=$asunto&body=$cuerpo');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
        );
    }
  }

  void _copiarTexto(String valor, String etiqueta) {
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

  /// Captura el ticket visual como archivo de IMAGEN PNG y lo comparte
  Future<void> _compartirComoImagen() async {
    if (_generandoImagen) return;
    setState(() => _generandoImagen = true);

    try {
      // Pequeña espera para asegurar que el RenderRepaintBoundary esté listo y pintado
      await Future.delayed(const Duration(milliseconds: 80));

      final boundary =
          _ticketKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        _compartirTextoFallback();
        return;
      }

      // Renderizar a imagen con escala 3.0 para que se vea súper nítido al enviar por WhatsApp
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        _compartirTextoFallback();
        return;
      }

      final pngBytes = byteData.buffer.asUint8List();
      final nombreArchivo =
          'ticket_gestopago_${widget.resultado.folioAutorizacion}.png';

      final xfile = XFile.fromData(
        pngBytes,
        mimeType: 'image/png',
        name: nombreArchivo,
      );

      final fechaStr =
          DateFormat('dd/MM/yyyy HH:mm:ss').format(widget.resultado.fecha);

      final buffer = StringBuffer()
        ..writeln('🧾 Comprobante Oficial GestoPago')
        ..writeln('🔐 Folio Autorización: ${widget.resultado.folioAutorizacion}')
        ..writeln('🆔 ID Tx: ${widget.resultado.idTx}')
        ..writeln('💵 Monto: \$${widget.resultado.monto.toStringAsFixed(2)} MXN')
        ..writeln('💳 Método: ${widget.resultado.detalleMetodoPago}')
        ..writeln('📅 Fecha: $fechaStr');

      await SharePlus.instance.share(
        ShareParams(
          files: [xfile],
          subject: 'Comprobante GestoPago ${widget.resultado.folioAutorizacion}',
          text: buffer.toString(),
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.darkPink,
            duration: const Duration(seconds: 2),
            content: const Text(
              '📸 ¡Comprobante listo en imagen PNG! Puedes compartirlo o guardarlo.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error al capturar/compartir imagen: $e');
      _compartirTextoFallback();
    } finally {
      if (mounted) setState(() => _generandoImagen = false);
    }
  }

  void _compartirTextoFallback() {
    final fechaStr =
        DateFormat('dd/MM/yyyy HH:mm:ss').format(widget.resultado.fecha);
    final buffer = StringBuffer()
      ..writeln('🧾 COMPROBANTE OFICIAL GESTOPAGO')
      ..writeln('GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V.')
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln('✅ ESTADO: TRANSACCIÓN APROBADA')
      ..writeln('🔐 FOLIO AUTORIZACIÓN: ${widget.resultado.folioAutorizacion}')
      ..writeln('🆔 ID TRANSACCIÓN: ${widget.resultado.idTx}')
      ..writeln('📦 SERVICIO: ${widget.resultado.producto.servicio}')
      ..writeln('🏷️ PRODUCTO: ${widget.resultado.producto.producto}')
      ..writeln('🔢 REFERENCIA: ${widget.resultado.referenciaDestino}')
      ..writeln('💵 MONTO PAGADO: \$${widget.resultado.monto.toStringAsFixed(2)} MXN')
      ..writeln('💳 MÉTODO DE PAGO: ${widget.resultado.detalleMetodoPago}')
      ..writeln('📅 FECHA Y HORA: $fechaStr')
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln(widget.resultado.legendOficial);

    SharePlus.instance.share(
      ShareParams(
        text: buffer.toString(),
        subject: 'Comprobante GestoPago ${widget.resultado.folioAutorizacion}',
      ),
    );
  }

  String get _etiquetaReferencia {
    if (widget.resultado.producto.idCatTipoServicio == '19') {
      return 'Referencia / Cliente';
    }
    switch (widget.resultado.producto.categoria) {
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
    final resultado = widget.resultado;
    final fechaStr = DateFormat('dd/MM/yyyy · HH:mm:ss').format(resultado.fecha);
    final tienePin =
        resultado.pinDigital != null && resultado.pinDigital!.trim().isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── ÁREA CAPTURADA COMO IMAGEN ─────────────────────────────
              RepaintBoundary(
                key: _ticketKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Encabezado de Ticket Oficial ──────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.darkPink,
                              resultado.producto.colorMarca,
                            ],
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
                                horizontal: 16,
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

                      // ── Borde perforado estilo recibo ─────────────────────
                      SizedBox(
                        height: 14,
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
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Caja de Folio Oficial de Autorización ───────
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
                                            fontSize: 16,
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

                            // ── Caja de PIN Digital (si aplica) ─────────────
                            if (tienePin) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF1A237E),
                                      Color(0xFF3949AB),
                                    ],
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
                                            backgroundColor:
                                                const Color(0xFFFFD54F),
                                            foregroundColor:
                                                const Color(0xFF1A237E),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            minimumSize: Size.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          onPressed: () => _copiarTexto(
                                            resultado.pinDigital!,
                                            'PIN Digital',
                                          ),
                                          icon: const Icon(
                                            Icons.copy_all_rounded,
                                            size: 16,
                                          ),
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

                            const SizedBox(height: 12),

                            // ── Detalles desglosados de la operación ─────────
                            _filaRecibo(
                              'Servicio:',
                              resultado.producto.servicio,
                              negrita: true,
                            ),
                            _filaRecibo('Producto:', resultado.producto.producto),
                            _filaRecibo(
                              'Categoría XML:',
                              '${resultado.producto.subcategoria} (Cat. ${resultado.producto.idCatTipoServicio})',
                            ),
                            _filaRecibo(
                              _etiquetaReferencia,
                              resultado.referenciaDestino,
                              negrita: true,
                            ),
                            _filaRecibo(
                              'Método de Pago:',
                              resultado.detalleMetodoPago,
                            ),
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
                            _filaRecibo(
                              'Switch Autorizador:',
                              'GESTOPAGO (sendTx.do · Cod 01)',
                            ),

                            const SizedBox(height: 10),

                            // ── Leyenda Oficial del XML (`legend`) ───────────
                            Container(
                              padding: const EdgeInsets.all(10),
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
                                        size: 13,
                                        color: AppTheme.textMuted,
                                      ),
                                      SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          'Leyenda Oficial Proveedor (<legend> XML):',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    resultado.legendOficial,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AppTheme.textDark,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            // ── Sello Digital decorativo ─────────────────────
                            Center(
                              child: Column(
                                children: [
                                  Text(
                                    '||| ||||| || |||||| ||||| ||| ||||||| |||',
                                    style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 2,
                                      color: Colors.grey.shade400,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'AUT: ${resultado.folioAutorizacion} · IDTX: ${resultado.idTx} · AUTORIZADO GESTOPAGO',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      color: Colors.grey.shade500,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ── Botones de Acción (Fuera de la imagen que se comparte) ──────
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.darkPink,
                        elevation: 2,
                        side: BorderSide(color: AppTheme.darkPink, width: 1.6),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _generandoImagen ? null : _compartirComoImagen,
                      icon: _generandoImagen
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.darkPink,
                              ),
                            )
                          : const Icon(Icons.image_rounded, size: 20),
                      label: Text(
                        _generandoImagen ? 'Generando...' : 'Compartir Imagen',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0288D1),
                        elevation: 2,
                        side: const BorderSide(color: Color(0xFF0288D1), width: 1.6),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _enviandoCorreo ? null : _enviarTicketPorCorreo,
                      icon: _enviandoCorreo
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0288D1),
                              ),
                            )
                          : const Icon(Icons.mark_email_read_rounded, size: 20),
                      label: Text(
                        _enviandoCorreo ? 'Enviando...' : 'Enviar Correo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.darkPink,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 20,
                  ),
                  label: const Text(
                    'Aceptar y Cerrar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
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
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
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
                fontSize: 12,
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
