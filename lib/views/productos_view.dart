import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../controllers/saldo_proveedor_controller.dart';
import '../repository/database_helper.dart';
import '../services/catalogo_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fondear_saldo_sheet.dart';
import '../widgets/product_image.dart';
import 'carrito_view.dart';
import 'gestopago_hub_view.dart';
import 'notificaciones_view.dart';

class ProductosView extends StatefulWidget {
  final int usuarioId;
  final String usuarioEmail;
  final String usuarioRol;

  const ProductosView({
    super.key,
    required this.usuarioId,
    required this.usuarioEmail,
    this.usuarioRol = 'lector',
  });

  @override
  State<ProductosView> createState() => _ProductosViewState();
}

class _ProductosViewState extends State<ProductosView> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _recomendados = [];
  bool _recomendacionPersonal = false;
  int _itemsCarrito = 0;
  bool _isLoading = true;
  bool _offline = false;
  DateTime? _ultimaSync;
  String _searchQuery = '';
  String? _categoria;

  bool get _puedeEditar => widget.usuarioRol == 'admin' || widget.usuarioRol == 'editor';

  @override
  void initState() {
    super.initState();
    _cargarCarrito();
    _cargarProductos();
  }

  /// Catálogo: API cuando hay internet, SQLite cuando no (modo offline).
  Future<void> _cargarProductos() async {
    setState(() => _isLoading = true);
    final r = await CatalogoService.instance.cargar();
    final (recomendados, personal) =
        await CatalogoService.instance.recomendar(widget.usuarioId, r.productos);
    if (!mounted) return;
    setState(() {
      _products = r.productos;
      _offline = r.offline;
      _ultimaSync = r.ultimaSincronizacion;
      _recomendados = recomendados;
      _recomendacionPersonal = personal;
      _isLoading = false;
    });
  }

  Future<void> _actualizarRecomendaciones() async {
    final (recomendados, personal) =
        await CatalogoService.instance.recomendar(widget.usuarioId, _products);
    if (mounted) {
      setState(() {
        _recomendados = recomendados;
        _recomendacionPersonal = personal;
      });
    }
  }

  Future<void> _cargarCarrito() async {
    final items = await DatabaseHelper.instance.obtenerCarrito(widget.usuarioId);
    if (mounted) setState(() => _itemsCarrito = items.length);
  }

  /// Agregar al carrito (SQLite; funciona también sin conexión)
  Future<void> _addToCart(Map<String, dynamic> product, int quantity) async {
    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa una cantidad válida')),
      );
      return;
    }

    await DatabaseHelper.instance.agregarAlCarrito(widget.usuarioId, {
      'id': product['id'],
      'nombre': product['nombre_product'],
      'precio': (product['precio'] as num).toDouble(),
      'cantidad': quantity,
      'imagen': product['imagen'],
    });
    await DatabaseHelper.instance.registrarInteraccion(widget.usuarioId, product['id'] as int, 'carrito');
    await _cargarCarrito();
    _actualizarRecomendaciones();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🛒 ${product['nombre_product']} agregado al carrito (x$quantity)'),
          backgroundColor: AppTheme.darkPink,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          action: SnackBarAction(label: 'Ver', textColor: Colors.white, onPressed: _abrirCarrito),
        ),
      );
    }
  }

  Future<void> _abrirCarrito() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CarritoView(usuarioId: widget.usuarioId, usuarioEmail: widget.usuarioEmail),
      ),
    );
    await _cargarCarrito();
    _actualizarRecomendaciones();
  }

  void _compartir(Map<String, dynamic> product) {
    final imagen = product['imagen']?.toString() ?? '';
    SharePlus.instance.share(
      ShareParams(
        text: '¡Mira este producto en Mi Tiendita! 🛍️\n\n'
            '${product['nombre_product']}\n'
            'Precio: \$${(product['precio'] as num).toStringAsFixed(2)} MXN\n'
            '${imagen.startsWith('http') ? imagen : ''}',
        subject: 'Producto de Mi Tiendita',
      ),
    );
  }

  List<String> get _categorias {
    final set = <String>{};
    for (final p in _products) {
      set.add(p['categoria'] as String? ?? 'General');
    }
    return set.toList()..sort();
  }

  List<Map<String, dynamic>> get _filteredProducts {
    final query = _searchQuery.toLowerCase();
    return _products.where((p) {
      if (_categoria != null && p['categoria'] != _categoria) return false;
      if (query.isEmpty) return true;
      final title = (p['nombre_product'] as String).toLowerCase();
      final cat = (p['categoria'] as String? ?? '').toLowerCase();
      return title.contains(query) || cat.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;
    final mostrarRecomendados = _recomendados.isNotEmpty && _searchQuery.isEmpty && _categoria == null;

    return Scaffold(
      backgroundColor: AppTheme.softPinkBg,
      appBar: AppBar(
        titleSpacing: 12,
        centerTitle: false,
        title: Row(
          children: [
            const Flexible(child: Text('🛍️ Mi Tiendita', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            _badgeRol(),
          ],
        ),
        actions: [
          const NotificacionesBoton(),
          IconButton(
            tooltip: 'Carrito',
            onPressed: _abrirCarrito,
            icon: Badge(
              isLabelVisible: _itemsCarrito > 0,
              label: Text('$_itemsCarrito'),
              backgroundColor: AppTheme.darkPink,
              child: Icon(Icons.shopping_cart_rounded, color: AppTheme.darkPink),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Buscar productos...',
                prefixIcon: Icon(Icons.search, color: AppTheme.darkPink),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.darkPink))
          : RefreshIndicator(
              color: AppTheme.darkPink,
              onRefresh: _cargarProductos,
              child: CustomScrollView(
                slivers: [
                  if (_offline) SliverToBoxAdapter(child: _bannerOffline()),
                  SliverToBoxAdapter(child: _bannerAccesoRapidoGestoPago()),
                  SliverToBoxAdapter(child: _filtroCategorias()),
                  if (mostrarRecomendados) SliverToBoxAdapter(child: _seccionRecomendados()),
                  if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          _products.isEmpty
                              ? 'No hay productos guardados.\nConéctate a internet y desliza hacia abajo.'
                              : 'No se encontraron productos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.darkPink, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.only(bottom: 90),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => RepaintBoundary(
                            child: _tarjetaProducto(filtered[index]),
                          ),
                          childCount: filtered.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: _puedeEditar
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.darkPink,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Nuevo Producto'),
              onPressed: _showAddProductDialog,
            )
          : null,
    );
  }

  Widget _bannerAccesoRapidoGestoPago() {
    final saldoCtrl = SaldoProveedorController.instance;
    return ListenableBuilder(
      listenable: saldoCtrl,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.cardBorderPink, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: AppTheme.cardBorderPink.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.softPinkBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: AppTheme.darkPink,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bolsa GestoPago (Recargas, Servicios y PINes)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        Text(
                          'Saldo Proveedor: \$${saldoCtrl.saldo.toStringAsFixed(2)} MXN',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: saldoCtrl.saldo > 0
                                ? AppTheme.darkPink
                                : const Color(0xFFC62828),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: AppTheme.softPinkBg,
                      foregroundColor: AppTheme.darkPink,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    onPressed: () => FondearSaldoSheet.mostrar(
                      context,
                      emailUsuario: widget.usuarioEmail,
                    ),
                    icon: const Icon(Icons.add_card_rounded, size: 15),
                    label: const Text(
                      'Fondear',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _botonAccesoGestoPago(
                      icono: Icons.phone_iphone_rounded,
                      etiqueta: 'Recargas',
                      seccion: 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _botonAccesoGestoPago(
                      icono: Icons.bolt_rounded,
                      etiqueta: 'Servicios',
                      seccion: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _botonAccesoGestoPago(
                      icono: Icons.card_giftcard_rounded,
                      etiqueta: 'PINes',
                      seccion: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _botonAccesoGestoPago({
    required IconData icono,
    required String etiqueta,
    required int seccion,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GestoPagoHubView(
              usuarioId: widget.usuarioId,
              usuarioEmail: widget.usuarioEmail,
              seccionInicial: seccion,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: AppTheme.softPinkBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorderPink),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 16, color: AppTheme.darkPink),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkPink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgeRol() {
    final rol = widget.usuarioRol;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: rol == 'admin' ? AppTheme.adminBg : rol == 'editor' ? AppTheme.editorBg : AppTheme.lectorBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        rol == 'admin' ? 'Admin' : rol == 'editor' ? 'Editor' : 'Comprador',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: rol == 'admin' ? AppTheme.adminText : rol == 'editor' ? AppTheme.editorText : AppTheme.lectorText,
        ),
      ),
    );
  }

  Widget _bannerOffline() {
    final cuando = _ultimaSync == null ? '' : ' (actualizado ${DateFormat('dd/MM HH:mm').format(_ultimaSync!)})';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFF9A825)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin conexión: mostrando el catálogo guardado$cuando. Puedes seguir agregando al carrito.',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF8D6E00)),
            ),
          ),
          IconButton(
            tooltip: 'Reintentar',
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFF9A825)),
            onPressed: _cargarProductos,
          ),
        ],
      ),
    );
  }

  Widget _filtroCategorias() {
    final cats = _categorias;
    if (cats.length < 2) return const SizedBox(height: 4);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        children: [
          _chipCategoria('Todas', null),
          for (final c in cats) _chipCategoria(c, c),
        ],
      ),
    );
  }

  Widget _chipCategoria(String texto, String? valor) {
    final sel = _categoria == valor;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(texto[0].toUpperCase() + texto.substring(1)),
        selected: sel,
        selectedColor: AppTheme.cardBorderPink,
        backgroundColor: Colors.white,
        side: BorderSide(color: AppTheme.cardBorderPink),
        labelStyle: TextStyle(
            fontSize: 12, color: sel ? AppTheme.darkPink : AppTheme.textDark, fontWeight: FontWeight.w600),
        onSelected: (_) => setState(() => _categoria = valor),
      ),
    );
  }

  Widget _seccionRecomendados() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Icon(_recomendacionPersonal ? Icons.auto_awesome_rounded : Icons.local_fire_department_rounded,
                  color: AppTheme.darkPink, size: 20),
              const SizedBox(width: 6),
              Text(
                _recomendacionPersonal ? 'Recomendado para ti' : 'Populares',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.darkPink),
              ),
              if (_recomendacionPersonal) ...[
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('según tus compras y búsquedas',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recomendados.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = _recomendados[i];
              return GestureDetector(
                onTap: () => _verDetalle(p),
                child: Container(
                  width: 130,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.cardBorderPink),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProductImage(
                        imageSource: p['imagen']?.toString(),
                        width: 130,
                        height: 105,
                        fit: BoxFit.contain,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                        child: Text(p['nombre_product'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Text('\$${(p['precio'] as num).toStringAsFixed(2)}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkPink)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
          child: Text('Todos los productos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.darkPink)),
        ),
      ],
    );
  }

  Widget _tarjetaProducto(Map<String, dynamic> product) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.cardBorderPink),
      ),
      elevation: 2,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _verDetalle(product),
        child: IntrinsicHeight(
          child: Row(
            children: [
              ProductImage(
                imageSource: product['imagen']?.toString(),
                width: 95,
                height: 95,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        product['nombre_product'],
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '\$${(product['precio'] as num).toStringAsFixed(2)} MXN',
                        style: TextStyle(color: AppTheme.darkPink, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${product['categoria']} · Stock: ${product['cantidad']}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _dialogoCantidad(product),
                      child: const Text('Comprar', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.share, color: AppTheme.darkPink, size: 18),
                          tooltip: 'Compartir',
                          onPressed: () => _compartir(product),
                        ),
                        if (_puedeEditar)
                          IconButton(
                            icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 18),
                            tooltip: 'Eliminar producto',
                            onPressed: () => _confirmarEliminarProducto(product),
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
    );
  }

  /// Detalle del producto (registra la vista para las recomendaciones).
  void _verDetalle(Map<String, dynamic> p) {
    DatabaseHelper.instance.registrarInteraccion(widget.usuarioId, p['id'] as int, 'vista');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ProductImage(
                imageSource: p['imagen']?.toString(),
                width: 220,
                height: 220,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),
            Text(p['nombre_product'] as String,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
            const SizedBox(height: 6),
            Text('\$${(p['precio'] as num).toStringAsFixed(2)} MXN',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkPink)),
            const SizedBox(height: 6),
            Chip(label: Text(p['categoria'] as String? ?? 'General'), backgroundColor: AppTheme.softPinkBg),
            const SizedBox(height: 10),
            Text((p['descripcion'] as String?)?.isNotEmpty == true ? p['descripcion'] as String : 'Sin descripción.',
                style: const TextStyle(color: AppTheme.textMuted, height: 1.4)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _compartir(p),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Compartir'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _dialogoCantidad(p);
                    },
                    icon: const Icon(Icons.add_shopping_cart_rounded),
                    label: const Text('Agregar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _dialogoCantidad(Map<String, dynamic> product) {
    final quantityController = TextEditingController(text: '1');
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Seleccionar Cantidad 🛍️',
            style: TextStyle(color: AppTheme.darkPink, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product['nombre_product'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Text('Precio: \$${(product['precio'] as num).toStringAsFixed(2)} MXN',
                  style: TextStyle(color: AppTheme.darkPink)),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Cantidad a comprar',
                  prefixIcon: const Icon(Icons.numbers),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                final quantity = int.tryParse(quantityController.text) ?? 1;
                Navigator.pop(ctx);
                _addToCart(product, quantity);
              },
              child: const Text('Agregar al Carrito'),
            ),
          ],
        );
      },
    );
  }

  void _confirmarEliminarProducto(Map<String, dynamic> p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Eliminar Producto', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16)),
          ],
        ),
        content: Text('¿Deseas eliminar "${p['nombre_product']}" del catálogo de Mi Tiendita?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await DatabaseHelper.instance.eliminarProducto(p['id'] as int);
              setState(() {
                _products.removeWhere((item) => item['id'] == p['id']);
                _recomendados.removeWhere((item) => item['id'] == p['id']);
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🗑️ Producto eliminado por ${widget.usuarioRol}'),
                    backgroundColor: Colors.red.shade400,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showAddProductDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddProductDialog(
        usuarioRol: widget.usuarioRol,
        onProductCreated: (nuevoProd) async {
          final id = await DatabaseHelper.instance.insertarProducto(
            nuevoProd['nombre_product'],
            nuevoProd['precio'],
            nuevoProd['imagen'],
            categoria: nuevoProd['categoria'],
            descripcion: nuevoProd['descripcion'],
          );
          nuevoProd['id'] = id;
          nuevoProd['origen'] = 'local';

          setState(() => _products.insert(0, nuevoProd));

          await NotificationService.instance.notificar(
            widget.usuarioId,
            '🆕 Nuevo producto publicado',
            '"${nuevoProd['nombre_product']}" ya está disponible en la tienda.',
            tipo: 'promociones',
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🌸 Producto "${nuevoProd['nombre_product']}" agregado con éxito'),
                backgroundColor: AppTheme.exito,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }
}

class _AddProductDialog extends StatefulWidget {
  final String usuarioRol;
  final Function(Map<String, dynamic>) onProductCreated;

  const _AddProductDialog({
    required this.usuarioRol,
    required this.onProductCreated,
  });

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _nombreCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _catCtrl = TextEditingController(text: 'General');
  final _descCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _selectedImage = 'https://fakestoreapi.com/img/81fPKd-2AYL._AC_SL1500_.jpg';
  bool _showUrlInput = false;

  final List<Map<String, String>> _presetPhotos = [
    {
      'label': '🎒 Bolso',
      'url': 'https://fakestoreapi.com/img/81fPKd-2AYL._AC_SL1500_.jpg',
    },
    {
      'label': '👗 Ropa',
      'url': 'https://fakestoreapi.com/img/71-3HjGNDUL._AC_SY879._SX._UX._SY._UY_.jpg',
    },
    {
      'label': '🧥 Chaqueta',
      'url': 'https://fakestoreapi.com/img/71li-ujtlUL._AC_UX679_.jpg',
    },
    {
      'label': '💍 Joyería',
      'url': 'https://fakestoreapi.com/img/71pWzhdJNwL._AC_UL640_QL65_ML3_.jpg',
    },
    {
      'label': '💎 Anillo',
      'url': 'https://fakestoreapi.com/img/61sbMiUnoGL._AC_UL640_QL65_ML3_.jpg',
    },
    {
      'label': '💻 Tech',
      'url': 'https://fakestoreapi.com/img/81QpkIctqPL._AC_SX679_.jpg',
    },
    {
      'label': '🎮 SSD',
      'url': 'https://fakestoreapi.com/img/61U7T1koQqL._AC_SX679_.jpg',
    },
  ];

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 85,
      );
      if (photo != null) {
        setState(() {
          _selectedImage = photo.path;
          _showUrlInput = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo acceder a la imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.add_business_rounded, color: AppTheme.darkPink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nuevo Producto (${widget.usuarioRol})',
              style: TextStyle(
                color: AppTheme.darkPink,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sección de Foto
              Text(
                '📸 Foto del Producto:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.darkPink,
                ),
              ),
              const SizedBox(height: 8),
              
              // Vista Previa de la Foto
              Center(
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: AppTheme.softPinkBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.cardBorderPink, width: 2),
                      ),
                      child: ProductImage(
                        imageSource: _selectedImage,
                        width: 130,
                        height: 130,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    if (_selectedImage.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedImage = '';
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Botones para Cámara / Galería / Enlace
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      side: BorderSide(color: AppTheme.darkPink),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(Icons.camera_alt_rounded, size: 18, color: AppTheme.darkPink),
                    label: Text('Cámara', style: TextStyle(fontSize: 12, color: AppTheme.darkPink)),
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      side: BorderSide(color: AppTheme.darkPink),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(Icons.photo_library_rounded, size: 18, color: AppTheme.darkPink),
                    label: Text('Galería', style: TextStyle(fontSize: 12, color: AppTheme.darkPink)),
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      side: BorderSide(color: AppTheme.darkPink),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(Icons.link_rounded, size: 18, color: AppTheme.darkPink),
                    label: Text('URL', style: TextStyle(fontSize: 12, color: AppTheme.darkPink)),
                    onPressed: () {
                      setState(() {
                        _showUrlInput = !_showUrlInput;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Campo para ingresar URL si se abre
              if (_showUrlInput) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlCtrl,
                        decoration: InputDecoration(
                          hintText: 'https://ejemplo.com/foto.jpg',
                          labelText: 'Enlace web de la imagen',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onPressed: () {
                        if (_urlCtrl.text.trim().isNotEmpty) {
                          setState(() {
                            _selectedImage = _urlCtrl.text.trim();
                            _showUrlInput = false;
                          });
                        }
                      },
                      child: const Text('Aplicar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Galería de fotos rápidas predeterminadas
              const Text(
                'O elige una foto de muestra:',
                style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _presetPhotos.map((preset) {
                    final isSelected = _selectedImage == preset['url'];
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedImage = preset['url']!;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.softPinkBg : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? AppTheme.darkPink : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                preset['url']!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, stack) => const Icon(Icons.image, size: 24),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              preset['label']!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? AppTheme.darkPink : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 24),

              // Campos del formulario
              TextField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre del producto',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _precioCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Precio (MXN)',
                  prefixIcon: Icon(Icons.attach_money),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _catCtrl,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final nombre = _nombreCtrl.text.trim();
            final precio = double.tryParse(_precioCtrl.text) ?? 0.0;
            final cat = _catCtrl.text.trim();

            if (nombre.isEmpty || precio <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Por favor ingresa un nombre y precio válido.')),
              );
              return;
            }

            final nuevoProd = <String, dynamic>{
              'nombre_product': nombre,
              'precio': precio,
              'cantidad': 1000,
              'imagen': _selectedImage.isEmpty
                  ? 'https://fakestoreapi.com/img/81fPKd-2AYL._AC_SL1500_.jpg'
                  : _selectedImage,
              'categoria': cat.isEmpty ? 'General' : cat,
              'descripcion': _descCtrl.text.trim().isEmpty
                  ? 'Producto publicado por ${widget.usuarioRol}'
                  : _descCtrl.text.trim(),
            };

            Navigator.pop(context);
            widget.onProductCreated(nuevoProd);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

