import 'package:flutter/material.dart';
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
    final cambioPaleta = _paletaActual != _settings.paleta.id;
    _paletaActual = _settings.paleta.id;
    setState(() {});
    if (cambioPaleta) {
      // Las vistas leen los colores directamente de AppTheme, así que
      // forzamos a que todas se reconstruyan con la nueva paleta.
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
