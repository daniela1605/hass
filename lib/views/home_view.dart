import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controllers/usuario_controller.dart';
import '../repository/database_helper.dart';
import '../services/auth_service.dart';
import '../services/catalogo_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'ajustes_view.dart';
import 'gestopago_hub_view.dart';
import 'historial_view.dart';
import 'login_view.dart';
import 'mapa_view.dart';
import 'productos_view.dart';
import 'usuario_lista_view.dart';

/// Cierra la sesión y regresa al login.
Future<void> cerrarSesion(BuildContext context) async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Cerrar sesión'),
      content: const Text('¿Seguro que quieres salir?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salir')),
      ],
    ),
  );
  if (confirmar != true || !context.mounted) return;
  await AuthService.instance.cerrarSesion();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginView()),
    (_) => false,
  );
}

class _Seccion {
  final String etiqueta;
  final IconData icono;
  final IconData iconoActivo;
  final Widget Function() constructor;
  _Seccion(this.etiqueta, this.icono, this.iconoActivo, this.constructor);
}

/// Pantalla principal con menú inferior. Las secciones dependen del rol.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _indice = 0;
  final Set<int> _visitadas = {0};
  late final List<_Seccion> _secciones;
  final _usuarioController = UsuarioController();

  @override
  void initState() {
    super.initState();
    final u = Sesion.instance.usuario!;
    _secciones = [
      if (u.rol == 'admin')
        _Seccion('Usuarios', Icons.people_outline_rounded, Icons.people_rounded,
            () => UsuarioListaView(controller: _usuarioController)),
      _Seccion('Tienda', Icons.storefront_outlined, Icons.storefront_rounded,
          () => ProductosView(usuarioId: u.id!, usuarioEmail: u.email, usuarioRol: u.rol)),
      _Seccion('GestoPago', Icons.bolt_outlined, Icons.bolt_rounded,
          () => GestoPagoHubView(usuarioId: u.id!, usuarioEmail: u.email)),
      _Seccion('Mapa', Icons.map_outlined, Icons.map_rounded, () => const MapaView()),
      _Seccion('Historial', Icons.receipt_long_outlined, Icons.receipt_long_rounded,
          () => HistorialView(usuarioId: u.id!, esAdmin: u.rol == 'admin')),
      _Seccion('Perfil', Icons.person_outline_rounded, Icons.person_rounded, () => const AjustesView()),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _alEntrar());
  }

  Future<void> _alEntrar() async {
    final u = Sesion.instance.usuario;
    if (u == null) return;
    await NotificationService.instance.pedirPermiso();
    await NotificationService.instance.actualizarContador(u.id!);
    await _promocionDelDia(u.id!);
  }

  /// Una notificación de promoción al día basada en las recomendaciones.
  Future<void> _promocionDelDia(int usuarioId) async {
    final prefs = await SharedPreferences.getInstance();
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    final clave = 'promo_${usuarioId}_$hoy';
    if (prefs.getBool(clave) == true) return;
    await Future.delayed(const Duration(seconds: 4)); // deja cargar la tienda primero
    final productos = (await DatabaseHelper.instance.listarProductos())
        .map(CatalogoService.aVista)
        .toList();
    final (recomendados, personal) =
        await CatalogoService.instance.recomendar(usuarioId, productos, max: 1);
    if (recomendados.isEmpty) return;
    await prefs.setBool(clave, true);
    final p = recomendados.first;
    await NotificationService.instance.notificar(
      usuarioId,
      personal ? '🎁 Elegido para ti' : '🔥 Promoción del día',
      '${p['nombre_product']} · \$${(p['precio'] as double).toStringAsFixed(2)} MXN. ¡Échale un vistazo en la tienda!',
      tipo: 'promociones',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _indice == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _indice = 0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _indice,
          children: [
            for (var i = 0; i < _secciones.length; i++)
              _visitadas.contains(i) ? _secciones[i].constructor() : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _indice,
          onDestinationSelected: (i) => setState(() {
            _indice = i;
            _visitadas.add(i);
          }),
          backgroundColor: Colors.white,
          indicatorColor: AppTheme.cardBorderPink,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final s in _secciones)
              NavigationDestination(
                icon: Icon(s.icono),
                selectedIcon: Icon(s.iconoActivo, color: AppTheme.darkPink),
                label: s.etiqueta,
              ),
          ],
        ),
      ),
    );
  }
}
