import 'package:flutter/material.dart';

/// Clasificación oficial por `idCatTipoServicio` del XML de GestoPago.
enum CategoriaGestoPago {
  recargas,
  servicios,
  pines,
  otros;

  String get etiqueta {
    switch (this) {
      case CategoriaGestoPago.recargas:
        return 'Recargas Telefónicas';
      case CategoriaGestoPago.servicios:
        return 'Pago de Servicios';
      case CategoriaGestoPago.pines:
        return 'Tarjetas Digitales y PINes';
      case CategoriaGestoPago.otros:
        return 'Otros Servicios';
    }
  }

  /// Clasifica según las reglas de negocio de GestoPago:
  /// - Recargas Telefónicas: ['13', '3']
  /// - Pago de Servicios: ['5', '15', '8', '9', '18', '19']
  /// - Tarjetas Digitales y PINes: ['10', '11', '16']
  static CategoriaGestoPago desdeIdCat(String idCatTipoServicio) {
    final id = idCatTipoServicio.trim();
    if (const ['13', '3'].contains(id)) {
      return CategoriaGestoPago.recargas;
    }
    if (const ['5', '15', '8', '9', '18', '19'].contains(id)) {
      return CategoriaGestoPago.servicios;
    }
    if (const ['10', '11', '16'].contains(id)) {
      return CategoriaGestoPago.pines;
    }
    return CategoriaGestoPago.otros;
  }

  static String nombreSubcategoriaServicio(String idCat) {
    switch (idCat.trim()) {
      case '5':
        return 'Electricidad (CFE)';
      case '15':
        return 'Agua Potable';
      case '8':
        return 'Gas Natural / LP';
      case '9':
        return 'Internet, TV y Telefonía';
      case '18':
        return 'Peajes y Tags';
      case '19':
        return 'Catálogo y Financiero';
      case '13':
        return 'Tiempo Aire';
      case '3':
        return 'Paquetes de Datos';
      case '10':
        return 'Entretenimiento y Streaming';
      case '11':
        return 'Gaming y Consolas';
      case '16':
        return 'Compras y Cine';
      default:
        return 'General';
    }
  }
}

/// Modelo que representa un nodo `<P>` del XML `<PRODUCTOS><P>...</P></PRODUCTOS>`
/// del proveedor GestoPago (`GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V.`).
class GestoPagoProducto {
  final String servicio;
  final String producto;
  final String idServicio;
  final String idProducto;
  final String idCatTipoServicio;
  final String tipoFront;
  final bool hasDigitoVerificador;
  final double precio;
  final bool showAyuda;
  final String tipoReferencia;
  final String legend;

  const GestoPagoProducto({
    required this.servicio,
    required this.producto,
    required this.idServicio,
    required this.idProducto,
    required this.idCatTipoServicio,
    required this.tipoFront,
    required this.hasDigitoVerificador,
    required this.precio,
    required this.showAyuda,
    required this.tipoReferencia,
    required this.legend,
  });

  CategoriaGestoPago get categoria =>
      CategoriaGestoPago.desdeIdCat(idCatTipoServicio);

  String get subcategoria =>
      CategoriaGestoPago.nombreSubcategoriaServicio(idCatTipoServicio);

  /// Indica si el producto tiene monto abierto (ej. pago de servicios donde precio == 0)
  bool get esMontoAbierto => precio <= 0 || tipoFront == '2';

  /// Clave única compuesta por servicio y producto
  String get uniqueKey => '${idServicio}_$idProducto';

  /// Color distintivo de la marca para tarjetas UI sin depender de red externa
  Color get colorMarca {
    final s = servicio.toLowerCase();
    if (s.contains('telcel')) return const Color(0xFF003399);
    if (s.contains('at&t') || s.contains('att')) return const Color(0xFF009FDB);
    if (s.contains('movistar')) return const Color(0xFF019DF4);
    if (s.contains('bait')) return const Color(0xFFFFB800);
    if (s.contains('unefon')) return const Color(0xFFE6007E);
    if (s.contains('virgin')) return const Color(0xFFE10A0A);
    if (s.contains('pillofon')) return const Color(0xFFFF5722);
    if (s.contains('cfe')) return const Color(0xFF00855A);
    if (s.contains('agua') || s.contains('sacmex') || s.contains('siapa')) {
      return const Color(0xFF0288D1);
    }
    if (s.contains('naturgy') || s.contains('gas')) return const Color(0xFFF57C00);
    if (s.contains('telmex') || s.contains('infinitum')) return const Color(0xFF005AA7);
    if (s.contains('totalplay')) return const Color(0xFF6A1B9A);
    if (s.contains('izzi')) return const Color(0xFFD81B60);
    if (s.contains('megacable') || s.contains('sky')) return const Color(0xFF1565C0);
    if (s.contains('pase') || s.contains('televia') || s.contains('tag')) {
      return const Color(0xFF2E7D32);
    }
    if (s.contains('coppel') || s.contains('elektra') || s.contains('avon')) {
      return const Color(0xFFC2185B);
    }
    if (s.contains('netflix')) return const Color(0xFFE50914);
    if (s.contains('spotify')) return const Color(0xFF1DB954);
    if (s.contains('amazon')) return const Color(0xFFFF9900);
    if (s.contains('xbox')) return const Color(0xFF107C10);
    if (s.contains('playstation') || s.contains('psn')) return const Color(0xFF00439C);
    if (s.contains('cinepolis') || s.contains('cinépolis')) return const Color(0xFF0B2265);
    if (s.contains('nintendo')) return const Color(0xFFE60012);
    if (s.contains('steam')) return const Color(0xFF171A21);
    if (s.contains('google play')) return const Color(0xFF01875F);
    if (s.contains('uber')) return const Color(0xFF212121);
    return const Color(0xFFEC407A);
  }

  /// Icono representativo para renderizado estático rápido a 60 FPS
  IconData get iconoMarca {
    final s = servicio.toLowerCase();
    switch (categoria) {
      case CategoriaGestoPago.recargas:
        if (producto.toLowerCase().contains('paquete') || idCatTipoServicio == '3') {
          return Icons.wifi_tethering_rounded;
        }
        return Icons.phone_iphone_rounded;
      case CategoriaGestoPago.servicios:
        if (s.contains('cfe') || idCatTipoServicio == '5') return Icons.bolt_rounded;
        if (s.contains('agua') || idCatTipoServicio == '15') return Icons.water_drop_rounded;
        if (s.contains('gas') || idCatTipoServicio == '8') {
          return Icons.local_fire_department_rounded;
        }
        if (idCatTipoServicio == '9') return Icons.router_rounded;
        if (idCatTipoServicio == '18') return Icons.directions_car_filled_rounded;
        return Icons.account_balance_rounded;
      case CategoriaGestoPago.pines:
        if (s.contains('netflix') || s.contains('cine')) return Icons.movie_filter_rounded;
        if (s.contains('spotify')) return Icons.headphones_rounded;
        if (s.contains('xbox') || s.contains('playstation') || s.contains('nintendo') || s.contains('steam')) {
          return Icons.sports_esports_rounded;
        }
        if (s.contains('amazon') || s.contains('google')) return Icons.card_giftcard_rounded;
        if (s.contains('uber')) return Icons.local_taxi_rounded;
        return Icons.redeem_rounded;
      case CategoriaGestoPago.otros:
        return Icons.receipt_long_rounded;
    }
  }

  Map<String, dynamic> toMap() => {
        'unique_key': uniqueKey,
        'servicio': servicio,
        'producto': producto,
        'id_servicio': idServicio,
        'id_producto': idProducto,
        'id_cat_tipo_servicio': idCatTipoServicio,
        'tipo_front': tipoFront,
        'has_digito_verificador': hasDigitoVerificador ? 1 : 0,
        'precio': precio,
        'show_ayuda': showAyuda ? 1 : 0,
        'tipo_referencia': tipoReferencia,
        'legend': legend,
      };

  factory GestoPagoProducto.fromMap(Map<String, dynamic> map) {
    return GestoPagoProducto(
      servicio: (map['servicio'] ?? '').toString(),
      producto: (map['producto'] ?? '').toString(),
      idServicio: (map['id_servicio'] ?? '1').toString(),
      idProducto: (map['id_producto'] ?? '1').toString(),
      idCatTipoServicio: (map['id_cat_tipo_servicio'] ?? '5').toString(),
      tipoFront: (map['tipo_front'] ?? '1').toString(),
      hasDigitoVerificador: (map['has_digito_verificador'] == 1 ||
          map['has_digito_verificador'] == true ||
          map['has_digito_verificador'] == 'true'),
      precio: map['precio'] is num
          ? (map['precio'] as num).toDouble()
          : double.tryParse((map['precio'] ?? '0').toString()) ?? 0.0,
      showAyuda: (map['show_ayuda'] == 1 ||
          map['show_ayuda'] == true ||
          map['show_ayuda'] == 'true'),
      tipoReferencia: (map['tipo_referencia'] ?? 'a').toString(),
      legend: (map['legend'] ?? '').toString(),
    );
  }
}

/// Respuesta de verificación de referencia (`confirmTx.do`)
class ConfirmacionReferenciaGestoPago {
  final bool valida;
  final String referencia;
  final String titular;
  final double saldoSugerido;
  final String fechaLimite;
  final String mensaje;
  final bool desdeSandbox;

  const ConfirmacionReferenciaGestoPago({
    required this.valida,
    required this.referencia,
    required this.titular,
    required this.saldoSugerido,
    required this.fechaLimite,
    required this.mensaje,
    this.desdeSandbox = true,
  });
}

/// Respuesta oficial al procesar una transacción (`sendTx.do`)
class ResultadoTransaccionGestoPago {
  final bool aprobada;
  final String folioAutorizacion; // NUM_AUTORIZACION o GP-AUTH-...
  final String idTx; // ID_TX del proveedor
  final String? pinDigital; // Solo para tarjetas digitales y PINes
  final GestoPagoProducto producto;
  final String referenciaDestino; // Teléfono, contrato o correo destino
  final double monto;
  final double comisionGanada;
  final String metodoPago; // 'saldo_proveedor' | 'paypal' | 'tarjeta' | 'wallet'
  final String detalleMetodoPago;
  final double saldoRestanteProveedor;
  final DateTime fecha;
  final String legendOficial;
  final bool modoRespaldo;

  const ResultadoTransaccionGestoPago({
    required this.aprobada,
    required this.folioAutorizacion,
    required this.idTx,
    this.pinDigital,
    required this.producto,
    required this.referenciaDestino,
    required this.monto,
    required this.comisionGanada,
    required this.metodoPago,
    required this.detalleMetodoPago,
    required this.saldoRestanteProveedor,
    required this.fecha,
    required this.legendOficial,
    this.modoRespaldo = false,
  });
}

/// Movimiento individual en la Bolsa de Saldo con Proveedor
class MovimientoSaldo {
  final String id;
  final String tipo; // 'abono' | 'cargo' | 'simulacion'
  final String concepto;
  final double monto;
  final double comision;
  final double saldoResultante;
  final String folio;
  final String metodoPago;
  final DateTime fecha;

  const MovimientoSaldo({
    required this.id,
    required this.tipo,
    required this.concepto,
    required this.monto,
    required this.comision,
    required this.saldoResultante,
    required this.folio,
    required this.metodoPago,
    required this.fecha,
  });

  bool get esAbono => tipo == 'abono';

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo,
        'concepto': concepto,
        'monto': monto,
        'comision': comision,
        'saldoResultante': saldoResultante,
        'folio': folio,
        'metodoPago': metodoPago,
        'fecha': fecha.toIso8601String(),
      };

  factory MovimientoSaldo.fromJson(Map<String, dynamic> json) {
    return MovimientoSaldo(
      id: (json['id'] ?? '').toString(),
      tipo: (json['tipo'] ?? 'cargo').toString(),
      concepto: (json['concepto'] ?? '').toString(),
      monto: (json['monto'] as num?)?.toDouble() ?? 0.0,
      comision: (json['comision'] as num?)?.toDouble() ?? 0.0,
      saldoResultante: (json['saldoResultante'] as num?)?.toDouble() ?? 0.0,
      folio: (json['folio'] ?? '').toString(),
      metodoPago: (json['metodoPago'] ?? '').toString(),
      fecha: DateTime.tryParse((json['fecha'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}
