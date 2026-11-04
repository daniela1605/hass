import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../controllers/saldo_proveedor_controller.dart';
import '../models/gestopago_models.dart';
import '../repository/database_helper.dart';
import '../services/gestopago_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fondear_saldo_sheet.dart';
import '../widgets/gestopago_ticket_dialog.dart';
import '../widgets/paypal_checkout_dialog.dart';
import 'notificaciones_view.dart';

/// Vista principal del módulo **GestoPago**:
/// - Recargas Telefónicas (`idCatTipoServicio`: `13`, `3`)
/// - Pago de Servicios (`idCatTipoServicio`: `5`, `15`, `8`, `9`, `18`, `19`)
/// - Tarjetas Digitales y PINes (`idCatTipoServicio`: `10`, `11`, `16`)
/// - Bolsa de Saldo con Proveedor (`SaldoProveedorController`)
class GestoPagoHubView extends StatefulWidget {
  final int usuarioId;
  final String usuarioEmail;
  final int seccionInicial; // 0: Recargas, 1: Servicios, 2: PINes, 3: Bolsa

  const GestoPagoHubView({
    super.key,
    required this.usuarioId,
    required this.usuarioEmail,
    this.seccionInicial = 0,
  });

  @override
  State<GestoPagoHubView> createState() => _GestoPagoHubViewState();
}

class _GestoPagoHubViewState extends State<GestoPagoHubView> {
  final _saldoCtrl = SaldoProveedorController.instance;
  final _gpService = GestoPagoService.instance;

  late int _tabIndex;
  bool _cargandoCatalogo = true;
  CatalogoGestoPagoResult? _catalogo;

  // Filtros interactivos
  String _busqueda = '';
  String? _operadorRecargaSel;
  String? _subcatServicioSel;
  String? _marcaPinSel;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.seccionInicial;
    _inicializarModulo();
  }

  Future<void> _inicializarModulo({bool forzarRed = false}) async {
    setState(() => _cargandoCatalogo = true);
    await _saldoCtrl.init();
    final cat = await _gpService.obtenerCatalogo(forzarRed: forzarRed);
    if (!mounted) return;
    setState(() {
      _catalogo = cat;
      _cargandoCatalogo = false;
    });
  }

  void _abrirModalFondeo() {
    FondearSaldoSheet.mostrar(context, emailUsuario: widget.usuarioEmail);
  }

  void _iniciarOperacionProducto(GestoPagoProducto producto) {
    // Validación temprana si la bolsa está en $0.00 MXN o si el producto tiene precio fijo mayor al saldo
    final montoMinimo = producto.precio > 0 ? producto.precio : 10.0;
    if (!_saldoCtrl.validarFondosConAlerta(
      context,
      montoRequerido: montoMinimo,
      conceptoOperacion: '${producto.servicio} - ${producto.producto}',
      onAbrirModalFondeo: _abrirModalFondeo,
    )) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormularioOperacionGestoPagoSheet(
        producto: producto,
        usuarioId: widget.usuarioId,
        usuarioEmail: widget.usuarioEmail,
        onAbrirFondeo: _abrirModalFondeo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softPinkBg,
      appBar: AppBar(
        titleSpacing: 12,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.softPinkBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorderPink),
              ),
              child: Icon(Icons.bolt_rounded, color: AppTheme.darkPink, size: 20),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Centro de Pagos GestoPago',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  Text(
                    'GESTO PAGO DE SERVICIOS, S.A.P.I. DE C.V.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronizar XML',
            onPressed: () => _inicializarModulo(forzarRed: true),
            icon: Icon(Icons.sync_rounded, color: AppTheme.darkPink),
          ),
          const NotificacionesBoton(),
        ],
      ),
      body: _cargandoCatalogo
          ? Center(child: CircularProgressIndicator(color: AppTheme.darkPink))
          : RefreshIndicator(
              color: AppTheme.darkPink,
              onRefresh: () => _inicializarModulo(forzarRed: true),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _bovedaSaldoHeader()),
                  SliverToBoxAdapter(child: _selectorSecciones()),
                  if (_tabIndex < 3) SliverToBoxAdapter(child: _barraBusqueda()),
                  SliverToBoxAdapter(child: _contenidoSeccionActiva()),
                  const SliverToBoxAdapter(child: SizedBox(height: 90)),
                ],
              ),
            ),
    );
  }

  // ─── 1. BÓVEDA DE SALDO CON PROVEEDOR (DISEÑO ÚNICO) ───────────────────────
  Widget _bovedaSaldoHeader() {
    return ListenableBuilder(
      listenable: _saldoCtrl,
      builder: (context, _) {
        final sinFondos = _saldoCtrl.saldo <= 0;
        final modoRespaldo = _catalogo?.modoRespaldo ?? true;

        return Container(
          margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: sinFondos
                  ? [const Color(0xFFB71C1C), const Color(0xFFE53935)]
                  : [AppTheme.darkPink, const Color(0xFF880E4F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: (sinFondos ? Colors.red : AppTheme.darkPink)
                    .withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fila superior: estado del switch XML y parámetros de comercio
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            modoRespaldo
                                ? Icons.storage_rounded
                                : Icons.cloud_done_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _catalogo?.origen ?? 'XML GestoPago',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Dist: 1 · Est: 1',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Saldo disponible y botón de Fondear
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'BOLSA DE SALDO CON PROVEEDOR',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.7,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '\$${_saldoCtrl.saldo.toStringAsFixed(2)} MXN',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sinFondos
                                ? '⚠️ Bolsa sin fondos: operaciones bloqueadas'
                                : 'Comisión ganada hoy: +\$${_saldoCtrl.comisionAcumulada.toStringAsFixed(2)} MXN (+\$2.50/op)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFFF59D),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: sinFondos
                            ? const Color(0xFFB71C1C)
                            : AppTheme.darkPink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _abrirModalFondeo,
                      icon: const Icon(Icons.add_card_rounded, size: 18),
                      label: const Text(
                        'Fondear',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Botones de simulación directa para pruebas de validación de fondos
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.science_rounded,
                        color: Colors.white70,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            await _saldoCtrl.reiniciarSaldoDemo();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(
                                const SnackBar(
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Color(0xFF2E7D32),
                                  content: Text(
                                    '✅ Simulación: Bolsa reiniciada a \$2,500.00 MXN',
                                  ),
                                ),
                              );
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '🔄 Reiniciar a \$2,500.00',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(width: 1, height: 16, color: Colors.white30),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            await _saldoCtrl.simularSaldoCero();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(
                                const SnackBar(
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Color(0xFFC62828),
                                  content: Text(
                                    '🛑 Simulación: Saldo \$0.00 MXN (Prueba de bloqueo activa)',
                                  ),
                                ),
                              );
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '⚠️ Simular Saldo \$0.00',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xFFFFCDD2),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
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

  // ─── 2. SELECTOR DE SECCIONES ──────────────────────────────────────────────
  Widget _selectorSecciones() {
    final tabs = [
      (icono: Icons.phone_iphone_rounded, titulo: 'Recargas', badge: 'Cat 13,3'),
      (icono: Icons.receipt_long_rounded, titulo: 'Servicios', badge: 'Cat 5-19'),
      (icono: Icons.card_giftcard_rounded, titulo: 'PINes', badge: 'Cat 10-16'),
      (icono: Icons.account_balance_wallet_rounded, titulo: 'Bolsa', badge: 'Movs'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final t = tabs[i];
          final sel = _tabIndex == i;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < tabs.length - 1 ? 6 : 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() {
                  _tabIndex = i;
                  _busqueda = '';
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppTheme.darkPink : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sel ? AppTheme.darkPink : AppTheme.cardBorderPink,
                    ),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                              color: AppTheme.darkPink.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        t.icono,
                        size: 20,
                        color: sel ? Colors.white : AppTheme.darkPink,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: sel ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                      Text(
                        t.badge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: sel ? Colors.white70 : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _barraBusqueda() {
    final hints = [
      'Buscar operador o monto (Telcel, AT&T, Bait, \$100...)',
      'Buscar servicio (CFE, SACMEX, Telmex, Totalplay, TAG...)',
      'Buscar tarjeta digital o PIN (Netflix, Spotify, Xbox, Cinépolis...)',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: TextField(
        onChanged: (v) => setState(() => _busqueda = v),
        decoration: InputDecoration(
          hintText: hints[_tabIndex],
          prefixIcon: Icon(Icons.search_rounded, color: AppTheme.darkPink),
          suffixIcon: _busqueda.isNotEmpty
              ? IconButton(
                  onPressed: () => setState(() => _busqueda = ''),
                  icon: const Icon(Icons.clear_rounded),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _contenidoSeccionActiva() {
    switch (_tabIndex) {
      case 0:
        return _seccionRecargas();
      case 1:
        return _seccionServicios();
      case 2:
        return _seccionPines();
      default:
        return _seccionBolsaMovimientos();
    }
  }

  // ─── SECCIÓN 0: RECARGAS TELEFÓNICAS (Cat 13 y 3) ──────────────────────────
  Widget _seccionRecargas() {
    final todos = _catalogo?.recargas ?? [];
    final operadores = todos.map((p) => p.servicio).toSet().toList();

    final filtrados = todos.where((p) {
      if (_operadorRecargaSel != null && p.servicio != _operadorRecargaSel) {
        return false;
      }
      if (_busqueda.trim().isEmpty) return true;
      final q = _busqueda.toLowerCase();
      return p.servicio.toLowerCase().contains(q) ||
          p.producto.toLowerCase().contains(q) ||
          p.precio.toStringAsFixed(0).contains(q);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          const Text(
            '1. Elige la compañía telefónica',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chipFiltro(
                  label: 'Todas (${todos.length})',
                  activo: _operadorRecargaSel == null,
                  onTap: () => setState(() => _operadorRecargaSel = null),
                ),
                for (final op in operadores)
                  _chipFiltro(
                    label: op,
                    activo: _operadorRecargaSel == op,
                    onTap: () => setState(() => _operadorRecargaSel = op),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '2. Selecciona el monto de Tiempo Aire o Paquete de Datos',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtrados.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.48,
            ),
            itemBuilder: (_, i) {
              final prod = filtrados[i];
              return RepaintBoundary(
                child: _tarjetaRecargaXml(prod),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tarjetaRecargaXml(GestoPagoProducto p) {
    final esPaquete = p.idCatTipoServicio == '3';
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _iniciarOperacionProducto(p),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.cardBorderPink, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: p.colorMarca.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: p.colorMarca.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(p.iconoMarca, color: p.colorMarca, size: 18),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p.servicio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: p.colorMarca,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: esPaquete
                        ? const Color(0xFFEDE7F6)
                        : const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    esPaquete ? 'Datos' : 'TAE',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: esPaquete
                          ? const Color(0xFF4527A0)
                          : const Color(0xFF0D47A1),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              p.producto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '\$${p.precio.toStringAsFixed(0)} MXN',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.darkPink,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: AppTheme.darkPink,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── SECCIÓN 1: PAGO DE SERVICIOS (Cat 5, 15, 8, 9, 18, 19) ────────────────
  Widget _seccionServicios() {
    final todos = _catalogo?.servicios ?? [];
    final subcats = [
      (id: '5', nombre: '⚡ Luz (CFE)'),
      (id: '15', nombre: '💧 Agua'),
      (id: '8', nombre: '🔥 Gas'),
      (id: '9', nombre: '🌐 Internet y TV'),
      (id: '18', nombre: '🛣️ Peajes y TAG'),
      (id: '19', nombre: '🛍️ Catálogo y Crédito'),
    ];

    final filtrados = todos.where((p) {
      if (_subcatServicioSel != null &&
          p.idCatTipoServicio != _subcatServicioSel) {
        return false;
      }
      if (_busqueda.trim().isEmpty) return true;
      final q = _busqueda.toLowerCase();
      return p.servicio.toLowerCase().contains(q) ||
          p.producto.toLowerCase().contains(q) ||
          p.subcategoria.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chipFiltro(
                  label: 'Todos (${todos.length})',
                  activo: _subcatServicioSel == null,
                  onTap: () => setState(() => _subcatServicioSel = null),
                ),
                for (final sc in subcats)
                  _chipFiltro(
                    label: sc.nombre,
                    activo: _subcatServicioSel == sc.id,
                    onTap: () => setState(() => _subcatServicioSel = sc.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtrados.length,
            itemBuilder: (_, i) {
              final s = filtrados[i];
              return RepaintBoundary(
                child: Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () => _iniciarOperacionProducto(s),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    leading: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: s.colorMarca.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(s.iconoMarca, color: s.colorMarca, size: 24),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.servicio,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.softPinkBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Cat ${s.idCatTipoServicio}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkPink,
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
                          s.producto,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.manage_search_rounded,
                              size: 14,
                              color: Color(0xFF0288D1),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${s.subcategoria} · Consulta en línea confirmTx.do',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF0288D1),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _iniciarOperacionProducto(s),
                      child: const Text('Pagar', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── SECCIÓN 2: TARJETAS DIGITALES Y PINES (Cat 10, 11, 16) ────────────────
  Widget _seccionPines() {
    final todos = _catalogo?.pines ?? [];
    final marcas = todos.map((p) => p.servicio).toSet().toList();

    final filtrados = todos.where((p) {
      if (_marcaPinSel != null && p.servicio != _marcaPinSel) return false;
      if (_busqueda.trim().isEmpty) return true;
      final q = _busqueda.toLowerCase();
      return p.servicio.toLowerCase().contains(q) ||
          p.producto.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chipFiltro(
                  label: 'Todas las marcas (${todos.length})',
                  activo: _marcaPinSel == null,
                  onTap: () => setState(() => _marcaPinSel = null),
                ),
                for (final m in marcas)
                  _chipFiltro(
                    label: m,
                    activo: _marcaPinSel == m,
                    onTap: () => setState(() => _marcaPinSel = m),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtrados.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.22,
            ),
            itemBuilder: (_, i) {
              final pin = filtrados[i];
              return RepaintBoundary(
                child: _tarjetaPinDigital(pin),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tarjetaPinDigital(GestoPagoProducto p) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _iniciarOperacionProducto(p),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.cardBorderPink),
          boxShadow: [
            BoxShadow(
              color: p.colorMarca.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    p.colorMarca,
                    p.colorMarca.withValues(alpha: 0.78),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Icon(p.iconoMarca, color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      p.servicio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.vpn_key_rounded,
                    color: Colors.white70,
                    size: 14,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.producto,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            '\$${p.precio.toStringAsFixed(2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.darkPink,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.softPinkBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Comprar PIN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkPink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SECCIÓN 3: HISTORIAL DE MOVIMIENTOS DE BOLSA ──────────────────────────
  Widget _seccionBolsaMovimientos() {
    return ListenableBuilder(
      listenable: _saldoCtrl,
      builder: (context, _) {
        final movs = _saldoCtrl.movimientos;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Historial de Movimientos de Saldo (Bolsa)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _abrirModalFondeo,
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                    label: const Text('Abonar'),
                  ),
                ],
              ),
              if (movs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: Text('No hay movimientos registrados aún.'),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: movs.length,
                  itemBuilder: (_, i) {
                    final m = movs[i];
                    final esAbono = m.tipo == 'abono';
                    final fechaStr =
                        DateFormat('dd/MM/yyyy HH:mm').format(m.fecha);
                    return RepaintBoundary(
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
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
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.concepto,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppTheme.textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
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
                                      'Método: ${m.metodoPago} · Saldo final: \$${m.saldoResultante.toStringAsFixed(2)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${esAbono ? '+' : '-'}\$${m.monto.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      color: esAbono
                                          ? const Color(0xFF2E7D32)
                                          : AppTheme.darkPink,
                                    ),
                                  ),
                                  if (m.comision > 0)
                                    Text(
                                      '+\$${m.comision.toStringAsFixed(2)} com.',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF2E7D32),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _chipFiltro({
    required String label,
    required bool activo,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: activo,
        selectedColor: AppTheme.cardBorderPink,
        backgroundColor: Colors.white,
        side: BorderSide(color: AppTheme.cardBorderPink),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: activo ? AppTheme.darkPink : AppTheme.textDark,
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FORMULARIO DE OPERACIÓN GESTOPAGO (RECARGAS, SERVICIOS Y PINES)
// Cumple estrictamente las reglas de inputFormatters, validación de Bolsa
// y el ciclo del Folio (NUNCA muestra ni permite editar un Folio antes del pago).
// ═════════════════════════════════════════════════════════════════════════════

class _FormularioOperacionGestoPagoSheet extends StatefulWidget {
  final GestoPagoProducto producto;
  final int usuarioId;
  final String usuarioEmail;
  final VoidCallback onAbrirFondeo;

  const _FormularioOperacionGestoPagoSheet({
    required this.producto,
    required this.usuarioId,
    required this.usuarioEmail,
    required this.onAbrirFondeo,
  });

  @override
  State<_FormularioOperacionGestoPagoSheet> createState() =>
      _FormularioOperacionGestoPagoSheetState();
}

class _FormularioOperacionGestoPagoSheetState
    extends State<_FormularioOperacionGestoPagoSheet> {
  final _formKey = GlobalKey<FormState>();
  final _saldoCtrl = SaldoProveedorController.instance;
  final _gpService = GestoPagoService.instance;

  // 1. Recargas Telefónicas
  final _telefonoCtrl = TextEditingController();
  final _confirmarTelCtrl = TextEditingController();

  // 2. Pago de Servicios
  final _referenciaCtrl = TextEditingController();
  late final TextEditingController _montoCtrl;
  ConfirmacionReferenciaGestoPago? _confirmacionRef;
  bool _consultandoRef = false;

  // 3. Tarjetas Digitales / PINes
  late final TextEditingController _correoDestinoCtrl;

  // 4. Método de pago seleccionado
  // 'saldo_proveedor' | 'paypal' | 'tarjeta' | 'wallet'
  String _metodoPago = 'saldo_proveedor';

  // Campos de Tarjeta de Crédito / Débito
  final _numTarjetaCtrl = TextEditingController();
  final _vencimientoCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();

  bool _procesandoPago = false;

  CategoriaGestoPago get _cat => widget.producto.categoria;

  @override
  void initState() {
    super.initState();
    _montoCtrl = TextEditingController(
      text: widget.producto.precio > 0
          ? widget.producto.precio.toStringAsFixed(2)
          : '',
    );
    _correoDestinoCtrl = TextEditingController(text: widget.usuarioEmail);
  }

  @override
  void dispose() {
    _telefonoCtrl.dispose();
    _confirmarTelCtrl.dispose();
    _referenciaCtrl.dispose();
    _montoCtrl.dispose();
    _correoDestinoCtrl.dispose();
    _numTarjetaCtrl.dispose();
    _vencimientoCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  double get _montoEfectivo {
    if (widget.producto.precio > 0 && !_esServicioMontoAbierto) {
      return widget.producto.precio;
    }
    return double.tryParse(_montoCtrl.text.trim()) ?? 0.0;
  }

  bool get _esServicioMontoAbierto =>
      _cat == CategoriaGestoPago.servicios || widget.producto.esMontoAbierto;

  String get _referenciaFinal {
    switch (_cat) {
      case CategoriaGestoPago.recargas:
        return _telefonoCtrl.text.trim();
      case CategoriaGestoPago.pines:
        return _correoDestinoCtrl.text.trim();
      case CategoriaGestoPago.servicios:
      case CategoriaGestoPago.otros:
        return _referenciaCtrl.text.trim().toUpperCase();
    }
  }

  // ─── Consulta de Referencia en `confirmTx.do` (Botón de Lupa) ──────────────
  Future<void> _consultarReferenciaEnSwitch() async {
    final ref = _referenciaCtrl.text.trim();
    if (!RegExp(r'^[a-zA-Z0-9]{6,30}$').hasMatch(ref)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFFC62828),
            content: Text(
              'Ingresa una referencia alfanumérica de 6 a 30 caracteres antes de consultar.',
            ),
          ),
        );
      return;
    }

    setState(() => _consultandoRef = true);
    final res = await _gpService.confirmarReferencia(
      producto: widget.producto,
      referencia: ref,
    );
    if (!mounted) return;
    setState(() {
      _consultandoRef = false;
      _confirmacionRef = res;
      if (_montoCtrl.text.trim().isEmpty || _montoEfectivo <= 0) {
        _montoCtrl.text = res.saldoSugerido.toStringAsFixed(2);
      }
    });
  }

  // ─── Validaciones estrictas de negocio ────────────────────────────────────
  String? _validarTelefono(String? value) {
    final v = (value ?? '').trim();
    if (!RegExp(r'^\d{10}$').hasMatch(v)) {
      return 'Debe contener exactamente 10 dígitos numéricos';
    }
    if (v.startsWith('0')) {
      return 'El número telefónico no puede iniciar en 0';
    }
    if (RegExp(r'^(\d)\1{9}$').hasMatch(v)) {
      return 'No se permiten 10 dígitos idénticos repetidos';
    }
    return null;
  }

  Future<void> _procesarOperacion() async {
    if (!_formKey.currentState!.validate()) return;

    final monto = _montoEfectivo;
    if (monto < 10.0 || monto > 50000.0) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFFC62828),
            content: Text('El monto debe estar entre \$10.00 y \$50,000.00 MXN'),
          ),
        );
      return;
    }

    // REGLA 2: Validación estricta de fondos ("Sí o sí debe disponer de dinero")
    if (!_saldoCtrl.validarFondosConAlerta(
      context,
      montoRequerido: monto,
      conceptoOperacion: '${widget.producto.servicio} (${widget.producto.producto})',
      onAbrirModalFondeo: () {
        Navigator.of(context).pop();
        widget.onAbrirFondeo();
      },
    )) {
      return;
    }

    String detalleMetodo = 'Saldo con Proveedor GestoPago';
    String? idPasarelaExterna;

    // Si eligió PayPal In-App, abrir primero el flujo interactivo de 3 pasos
    if (_metodoPago == 'paypal') {
      final resPayPal = await PayPalCheckoutDialog.mostrar(
        context,
        monto: monto,
        concepto: '${widget.producto.servicio} · ${widget.producto.producto}',
        emailSugerido: widget.usuarioEmail,
      );
      if (resPayPal == null || !mounted) return;
      detalleMetodo = resPayPal.resumen;
      idPasarelaExterna = resPayPal.payId;
    } else if (_metodoPago == 'tarjeta') {
      final ultimos4 = _numTarjetaCtrl.text.substring(12);
      detalleMetodo = 'Tarjeta •••• $ultimos4 (Vence ${_vencimientoCtrl.text})';
    } else if (_metodoPago == 'wallet') {
      detalleMetodo = 'Apple Pay / Google Wallet (Token Biometric)';
    }

    setState(() => _procesandoPago = true);

    try {
      // Saldo estimado tras descontar el monto y sumar la comisión de +$2.50 MXN
      final saldoRestanteEstimado =
          _saldoCtrl.saldo - monto + SaldoProveedorController.comisionPorOperacion;

      // 1. Ejecutar `sendTx.do` en GestoPagoService.
      // El Folio de Autorización es generado y retornado ÚNICAMENTE aquí.
      final resultadoTx = await _gpService.procesarTransaccion(
        producto: widget.producto,
        referencia: _referenciaFinal,
        monto: monto,
        metodoPago: _metodoPago,
        detalleMetodoPago: detalleMetodo,
        saldoRestanteProveedor: saldoRestanteEstimado,
        comisionGanada: SaldoProveedorController.comisionPorOperacion,
        idTransaccionPasarela: idPasarelaExterna,
      );

      // 2. Descontar de la Bolsa de Saldo con Proveedor y registrar comisión +$2.50 MXN
      await _saldoCtrl.descontarSaldo(
        monto: monto,
        concepto:
            '${widget.producto.servicio}: ${widget.producto.producto} ($_referenciaFinal)',
        folioOficial: resultadoTx.folioAutorizacion,
        metodoPago: detalleMetodo,
      );

      // 3. Guardar en el Historial de Compras SQLite con el Folio Oficial
      final itemHistorial = [
        {
          'nombre': '${widget.producto.servicio} - ${widget.producto.producto}',
          'precio': monto,
          'cantidad': 1,
          'referencia': _referenciaFinal,
          'folio': resultadoTx.folioAutorizacion,
          'id_tx': resultadoTx.idTx,
          'pin': resultadoTx.pinDigital,
          'legend': resultadoTx.legendOficial,
        }
      ];

      await DatabaseHelper.instance.guardarCompra(
        widget.usuarioId,
        jsonEncode(itemHistorial),
        monto,
        resultadoTx.folioAutorizacion,
        metodoPago: _metodoPago,
        detallePago:
            '$detalleMetodo · Ref: $_referenciaFinal · Folio: ${resultadoTx.folioAutorizacion}'
            '${resultadoTx.pinDigital != null ? ' · PIN: ${resultadoTx.pinDigital}' : ''}',
        estadoPago: 'aprobado',
      );

      // 4. Notificación local en tiempo real
      await NotificationService.instance.notificar(
        widget.usuarioId,
        '✅ ${widget.producto.servicio} autorizado',
        'Folio ${resultadoTx.folioAutorizacion} · \$${monto.toStringAsFixed(2)} MXN · Ref: $_referenciaFinal',
        tipo: 'compras',
      );

      if (!mounted) return;
      setState(() => _procesandoPago = false);

      // Cerrar formulario y desplegar el Ticket Oficial GestoPagoTicketDialog
      final navigator = Navigator.of(context);
      final rootContext = navigator.context;
      navigator.pop();
      if (rootContext.mounted) {
        await GestoPagoTicketDialog.mostrar(rootContext, resultadoTx);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesandoPago = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            content: Text('Error al procesar transacción: $e'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
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

                // Encabezado del servicio seleccionado
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: widget.producto.colorMarca.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        widget.producto.iconoMarca,
                        color: widget.producto.colorMarca,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.producto.servicio,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: widget.producto.colorMarca,
                            ),
                          ),
                          Text(
                            widget.producto.producto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textDark,
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

                const SizedBox(height: 12),

                // Aviso de seguridad sobre el ciclo del Folio
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.softPinkBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorderPink),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_rounded, size: 16, color: AppTheme.darkPink),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'El Folio de Autorización oficial será generado por GestoPago únicamente al aprobarse la transacción.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: AppTheme.textDark),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Campos específicos según categoría XML
                if (_cat == CategoriaGestoPago.recargas) _camposRecargaTelefonica(),
                if (_cat == CategoriaGestoPago.servicios ||
                    _cat == CategoriaGestoPago.otros)
                  _camposPagoServicio(),
                if (_cat == CategoriaGestoPago.pines) _camposPinDigital(),

                const SizedBox(height: 16),

                // Selección de Método de Pago (4 opciones requeridas)
                const Text(
                  'Método de Pago',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                _gridMetodosPago(),

                if (_metodoPago == 'tarjeta') ...[
                  const SizedBox(height: 14),
                  _formularioTarjeta(),
                ],

                if (_metodoPago == 'wallet') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.contactless_rounded, color: Color(0xFF6A1B9A)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Token de Apple Pay / Google Wallet listo para autenticar y liquidar operación.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF4A148C)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Botón de Confirmación
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _procesandoPago ? null : _procesarOperacion,
                    icon: _procesandoPago
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.bolt_rounded),
                    label: Text(
                      _procesandoPago
                          ? 'Autorizando con GestoPago XML...'
                          : _metodoPago == 'paypal'
                              ? 'Pagar con PayPal \$${_montoEfectivo.toStringAsFixed(2)} MXN'
                              : 'Autorizar Pago \$${_montoEfectivo.toStringAsFixed(2)} MXN',
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

  // ── 1. Campos de Recargas Telefónicas ─────────────────────────────────────
  Widget _camposRecargaTelefonica() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _telefonoCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: const InputDecoration(
            labelText: 'Número Telefónico (10 dígitos)',
            prefixIcon: Icon(Icons.phone_android_rounded),
            hintText: '5512345678',
          ),
          validator: _validarTelefono,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _confirmarTelCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: const InputDecoration(
            labelText: 'Confirmar Número Telefónico',
            prefixIcon: Icon(Icons.verified_outlined),
            hintText: 'Repite los 10 dígitos',
          ),
          validator: (v) {
            final baseErr = _validarTelefono(v);
            if (baseErr != null) return baseErr;
            if ((v ?? '').trim() != _telefonoCtrl.text.trim()) {
              return 'Los números telefónicos no coinciden';
            }
            return null;
          },
        ),
      ],
    );
  }

  // ── 2. Campos de Pago de Servicios (con lupa confirmTx.do) ─────────────────
  Widget _camposPagoServicio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _referenciaCtrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                  LengthLimitingTextInputFormatter(30),
                ],
                decoration: const InputDecoration(
                  labelText: 'Referencia / Contrato (6-30 alfanum.)',
                  prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                  hintText: 'Ej. CFE982341029',
                ),
                validator: (v) {
                  final val = (v ?? '').trim();
                  if (!RegExp(r'^[a-zA-Z0-9]{6,30}$').hasMatch(val)) {
                    return 'Obligatorio: 6 a 30 caracteres alfanuméricos';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0288D1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _consultandoRef ? null : _consultarReferenciaEnSwitch,
                child: _consultandoRef
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search_rounded),
              ),
            ),
          ],
        ),
        if (_confirmacionRef != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE1F5FE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF81D4FA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF0277BD),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Titular: ${_confirmacionRef!.titular}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Color(0xFF01579B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Adeudo consultado: \$${_confirmacionRef!.saldoSugerido.toStringAsFixed(2)} MXN · Vence: ${_confirmacionRef!.fechaLimite}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF0277BD)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: _montoCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Monto a pagar (\$10.00 - \$50,000.00 MXN)',
            prefixIcon: Icon(Icons.attach_money_rounded),
            suffixText: 'MXN',
          ),
          validator: (v) {
            final val = double.tryParse((v ?? '').trim());
            if (val == null || val < 10.0 || val > 50000.0) {
              return 'El monto debe estar entre \$10.00 y \$50,000.00 MXN';
            }
            return null;
          },
        ),
      ],
    );
  }

  // ── 3. Campos de Tarjetas Electrónicas / PINes Digitales ──────────────────
  Widget _camposPinDigital() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _correoDestinoCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Correo Electrónico destino para entrega del PIN',
            prefixIcon: Icon(Icons.mark_email_read_outlined),
            hintText: 'cliente@correo.com',
          ),
          validator: (v) {
            final val = (v ?? '').trim();
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(val)) {
              return 'Ingresa un correo electrónico válido para recibir el PIN';
            }
            return null;
          },
        ),
      ],
    );
  }

  // ── 4. Selector de los 4 Métodos de Pago ──────────────────────────────────
  Widget _gridMetodosPago() {
    final opciones = [
      (
        id: 'saldo_proveedor',
        nombre: 'Saldo GestoPago',
        sub: '\$${_saldoCtrl.saldo.toStringAsFixed(2)} disp.',
        icono: Icons.account_balance_wallet_rounded,
      ),
      (
        id: 'paypal',
        nombre: 'PayPal In-App',
        sub: 'Checkout 3 pasos',
        icono: Icons.payments_rounded,
      ),
      (
        id: 'tarjeta',
        nombre: 'Tarjeta Créd/Déb',
        sub: 'Visa / MC 16 díg.',
        icono: Icons.credit_card_rounded,
      ),
      (
        id: 'wallet',
        nombre: 'Apple / Google Pay',
        sub: 'Pago sin contacto',
        icono: Icons.contactless_rounded,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.45,
      children: [
        for (final op in opciones)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _metodoPago = op.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _metodoPago == op.id ? AppTheme.softPinkBg : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _metodoPago == op.id
                      ? AppTheme.darkPink
                      : AppTheme.cardBorderPink,
                  width: _metodoPago == op.id ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    op.icono,
                    size: 20,
                    color: _metodoPago == op.id
                        ? AppTheme.darkPink
                        : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          op.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _metodoPago == op.id
                                ? AppTheme.darkPink
                                : AppTheme.textDark,
                          ),
                        ),
                        Text(
                          op.sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _formularioTarjeta() {
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
            if (_metodoPago != 'tarjeta') return null;
            if (!RegExp(r'^\d{16}$').hasMatch((v ?? '').trim())) {
              return 'Exactamente 16 dígitos numéricos';
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
                  prefixIcon: Icon(Icons.event_rounded),
                  hintText: '12/28',
                ),
                validator: (v) {
                  if (_metodoPago != 'tarjeta') return null;
                  if (!RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$')
                      .hasMatch((v ?? '').trim())) {
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
                  if (_metodoPago != 'tarjeta') return null;
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
    );
  }
}
