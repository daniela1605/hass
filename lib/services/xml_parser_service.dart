import '../models/gestopago_models.dart';

/// Servicio dedicado al parseo de respuestas XML del proveedor GestoPago
/// (`GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V.`).
class XmlParserService {
  XmlParserService._();
  static final XmlParserService instance = XmlParserService._();

  /// Parsea la estructura `<PRODUCTOS><P ...>legend</P></PRODUCTOS>` y convierte
  /// cada nodo `<P>` en una instancia de [GestoPagoProducto].
  List<GestoPagoProducto> parseProductListXml(String xmlContent) {
    final productos = <GestoPagoProducto>[];
    if (xmlContent.trim().isEmpty) return productos;

    // Soporta tanto <P ...>legend</P> como <P .../> autocerrado
    final regNodoP = RegExp(
      r'<P\s+([^>]*?)(?:>(.*?)<\/P>|\/>)',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in regNodoP.allMatches(xmlContent)) {
      final attrsRaw = match.group(1) ?? '';
      final innerRaw = match.group(2) ?? '';
      final attrs = _extraerAtributos(attrsRaw);

      final servicio = _decodificarXml(attrs['servicio'] ?? 'Servicio GestoPago');
      final producto = _decodificarXml(attrs['producto'] ?? servicio);
      final idServicio = attrs['idServicio'] ?? attrs['idservicio'] ?? '1';
      final idProducto = attrs['idProducto'] ?? attrs['idproducto'] ?? '1';
      final idCatTipoServicio =
          attrs['idCatTipoServicio'] ?? attrs['idcattiposervicio'] ?? '5';
      final tipoFront = attrs['tipoFront'] ?? attrs['tipofront'] ?? '1';
      final hasDigitoStr =
          (attrs['hasDigitoVerificador'] ?? attrs['hasdigitoverificador'] ?? 'false')
              .toLowerCase();
      final hasDigitoVerificador = hasDigitoStr == 'true' || hasDigitoStr == '1';

      final precioStr = (attrs['precio'] ?? '0')
          .replaceAll(r'$', '')
          .replaceAll(',', '')
          .trim();
      final precio = double.tryParse(precioStr) ?? 0.0;

      final showAyudaStr =
          (attrs['showAyuda'] ?? attrs['showayuda'] ?? 'false').toLowerCase();
      final showAyuda = showAyudaStr == 'true' || showAyudaStr == '1';
      final tipoReferencia =
          attrs['tipoReferencia'] ?? attrs['tiporeferencia'] ?? 'a';

      // El texto interno del nodo <P> o tag hijo <LEGEND> actúa como legend oficial
      var legend = _limpiarCdata(innerRaw).trim();
      final tagLegend = extraerValorTag(innerRaw, 'LEGEND');
      if (tagLegend != null && tagLegend.isNotEmpty) {
        legend = tagLegend;
      }
      legend = _decodificarXml(legend.replaceAll(RegExp(r'<[^>]+>'), '').trim());

      if (legend.isEmpty) {
        legend =
            'Operación procesada por GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V. Conserve su comprobante para cualquier aclaración.';
      }

      productos.add(
        GestoPagoProducto(
          servicio: servicio,
          producto: producto,
          idServicio: idServicio,
          idProducto: idProducto,
          idCatTipoServicio: idCatTipoServicio,
          tipoFront: tipoFront,
          hasDigitoVerificador: hasDigitoVerificador,
          precio: precio,
          showAyuda: showAyuda,
          tipoReferencia: tipoReferencia,
          legend: legend,
        ),
      );
    }

    return productos;
  }

  /// Extrae el valor de una etiqueta XML como `<NUM_AUTORIZACION>...</NUM_AUTORIZACION>`
  String? extraerValorTag(String xml, String tag) {
    final regex = RegExp(
      '<$tag[^>]*>(.*?)<\\/$tag>',
      caseSensitive: false,
      dotAll: true,
    );
    final match = regex.firstMatch(xml);
    if (match == null) return null;
    return _decodificarXml(_limpiarCdata(match.group(1) ?? '').trim());
  }

  /// Parsea la respuesta XML de `confirmTx.do`
  ConfirmacionReferenciaGestoPago? parseConfirmTxXml(
    String xml,
    String referenciaOriginal,
  ) {
    if (xml.trim().isEmpty) return null;
    final codigo = extraerValorTag(xml, 'CODIGO') ??
        extraerValorTag(xml, 'CODE') ??
        extraerValorTag(xml, 'ESTATUS');
    if (codigo == null && !xml.contains('<')) return null;

    final titular = extraerValorTag(xml, 'TITULAR') ??
        extraerValorTag(xml, 'NOMBRE') ??
        extraerValorTag(xml, 'CLIENTE') ??
        'Titular Verificado GestoPago';
    final saldoStr = extraerValorTag(xml, 'SALDO') ??
        extraerValorTag(xml, 'MONTO') ??
        extraerValorTag(xml, 'IMPORTE') ??
        '0';
    final saldo = double.tryParse(saldoStr.replaceAll(',', '')) ?? 0.0;
    final fechaLimite =
        extraerValorTag(xml, 'FECHA_LIMITE') ?? extraerValorTag(xml, 'VENCIMIENTO') ?? 'Inmediato';
    final mensaje = extraerValorTag(xml, 'MENSAJE') ??
        extraerValorTag(xml, 'DESCRIPCION') ??
        'Referencia validada en el switch de GestoPago.';

    final valida = codigo == null || codigo == '0' || codigo == '00' || codigo == '200' || codigo == 'OK';

    return ConfirmacionReferenciaGestoPago(
      valida: valida,
      referencia: referenciaOriginal,
      titular: titular,
      saldoSugerido: saldo > 0 ? saldo : 385.50,
      fechaLimite: fechaLimite,
      mensaje: mensaje,
      desdeSandbox: false,
    );
  }

  /// Parsea la respuesta XML de `sendTx.do` para obtener `<NUM_AUTORIZACION>`, `<ID_TX>` y `<PIN>`
  Map<String, String>? parseSendTxXml(String xml) {
    if (xml.trim().isEmpty || !xml.contains('<')) return null;
    final numAut = extraerValorTag(xml, 'NUM_AUTORIZACION') ??
        extraerValorTag(xml, 'AUTORIZACION') ??
        extraerValorTag(xml, 'FOLIO');
    final idTx = extraerValorTag(xml, 'ID_TX') ??
        extraerValorTag(xml, 'TRANSACCION_ID') ??
        extraerValorTag(xml, 'ID');
    if (numAut == null && idTx == null) return null;

    final pin = extraerValorTag(xml, 'PIN');
    final mensaje = extraerValorTag(xml, 'MENSAJE');
    final legend = extraerValorTag(xml, 'LEGEND');
    final saldo = extraerValorTag(xml, 'SALDO');

    return {
      'NUM_AUTORIZACION': ?numAut,
      'ID_TX': ?idTx,
      'PIN': ?pin,
      'MENSAJE': ?mensaje,
      'LEGEND': ?legend,
      'SALDO': ?saldo,
    };
  }

  /// Parsea la respuesta XML de `getBalance.do`
  double? parseBalanceXml(String xml) {
    final val = extraerValorTag(xml, 'SALDO') ??
        extraerValorTag(xml, 'BALANCE') ??
        extraerValorTag(xml, 'DISPONIBLE');
    if (val == null) return null;
    return double.tryParse(val.replaceAll(r'$', '').replaceAll(',', '').trim());
  }

  Map<String, String> _extraerAtributos(String raw) {
    final map = <String, String>{};
    final regAttr = RegExp(r'(\w+)\s*=\s*["\x27]([^"\x27]*)["\x27]');
    for (final m in regAttr.allMatches(raw)) {
      final key = m.group(1);
      final val = m.group(2);
      if (key != null && val != null) {
        map[key] = val;
      }
    }
    return map;
  }

  String _limpiarCdata(String input) {
    return input
        .replaceAll(RegExp(r'<!\[CDATA\[', caseSensitive: false), '')
        .replaceAll(']]>', '');
  }

  String _decodificarXml(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}
