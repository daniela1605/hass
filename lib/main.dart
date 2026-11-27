import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'config/app_config.dart';
import 'controllers/saldo_proveedor_controller.dart';
import 'repository/database_helper.dart';
import 'services/app_settings.dart';
import 'services/notification_service.dart';
import 'services/security_service.dart';
import 'theme/app_theme.dart';
import 'views/login_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  debugPrint('[Config] ${AppConfig.resumen}');
  await SecurityService.init(); // clave AES para cifrar datos personales
  await AppSettings.instance.cargar(); // preferencias del usuario
  await SaldoProveedorController.instance.init(); // bolsa de saldo con proveedor GestoPago
  await NotificationService.instance.init();
  try {
    await DatabaseHelper.instance.sincronizarUsuariosDemo(); // correos de prueba (env.json)
  } catch (e) {
    debugPrint('No se pudieron sincronizar los usuarios de prueba: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _settings = AppSettings.instance;
  String _paletaActual = AppSettings.instance.paleta.id;
  bool _modoOscuroActual = AppSettings.instance.modoOscuro;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_alCambiarAjustes);
  }

  @override
  void dispose() {
    _settings.removeListener(_alCambiarAjustes);
    super.dispose();
  }

  void _alCambiarAjustes() {
    final cambio = _paletaActual != _settings.paleta.id || _modoOscuroActual != _settings.modoOscuro;
    _paletaActual = _settings.paleta.id;
    _modoOscuroActual = _settings.modoOscuro;
    setState(() {});
    if (cambio) {
      // Las vistas leen los colores directamente de AppTheme, así que
      // forzamos a que todas se reconstruyan con la nueva paleta o modo oscuro.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        void reconstruir(Element e) {
          e.markNeedsBuild();
          e.visitChildren(reconstruir);
        }
        if (mounted) (context as Element).visitChildren(reconstruir);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Tiendita',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.pastelPinkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _settings.modoOscuro ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(_settings.escalaTexto)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const LoginView(),
    );
  }
}
