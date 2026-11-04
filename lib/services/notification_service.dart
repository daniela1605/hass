import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../repository/database_helper.dart';
import 'app_settings.dart';

/// Notificaciones en tiempo real:
///  * Notificación del sistema (barra de estado) con flutter_local_notifications.
///  * Bandeja interna guardada en SQLite (pantalla "Notificaciones").
///  * Contador de no leídas para el ícono de campana.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final ValueNotifier<int> noLeidas = ValueNotifier<int>(0);
  bool _iniciado = false;
  int _siguienteId = 0;

  static const _canales = {
    'seguridad': ('seguridad', 'Seguridad', 'Inicios de sesión, cambios de contraseña y códigos'),
    'compras': ('compras', 'Compras', 'Confirmaciones de pedidos'),
    'promociones': ('promociones', 'Promociones', 'Ofertas y recomendaciones'),
    'sistema': ('sistema', 'General', 'Avisos generales de la app'),
  };

  Future<void> init() async {
    if (_iniciado) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
      _iniciado = true;
    } catch (e) {
      debugPrint('No se pudieron iniciar las notificaciones: $e');
    }
  }

  /// Pide permiso de notificaciones (Android 13+ / iOS).
  Future<void> pedirPermiso() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('Permiso de notificaciones: $e');
    }
  }

  /// Muestra solo la notificación del sistema (sin guardar en la bandeja).
  /// Útil para el "SMS simulado" del modo demo.
  Future<void> mostrarSistema(String titulo, String cuerpo, {String tipo = 'sistema'}) async {
    if (!_iniciado) return;
    final canal = _canales[tipo] ?? _canales['sistema']!;
    try {
      await _plugin.show(
        _siguienteId++,
        titulo,
        cuerpo,
        NotificationDetails(
          android: AndroidNotificationDetails(
            canal.$1,
            canal.$2,
            channelDescription: canal.$3,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(cuerpo),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Error mostrando notificación: $e');
    }
  }

  /// Guarda la notificación en la bandeja del usuario y la muestra si sus
  /// preferencias lo permiten.
  Future<void> notificar(int usuarioId, String titulo, String cuerpo,
      {String tipo = 'sistema'}) async {
    if (!AppSettings.instance.permite(tipo)) return;
    try {
      await DatabaseHelper.instance.insertarNotificacion(usuarioId, titulo, cuerpo, tipo);
      await actualizarContador(usuarioId);
    } catch (e) {
      debugPrint('Error guardando notificación: $e');
    }
    await mostrarSistema(titulo, cuerpo, tipo: tipo);
  }

  Future<void> actualizarContador(int usuarioId) async {
    noLeidas.value = await DatabaseHelper.instance.contarNoLeidas(usuarioId);
  }

  Future<void> marcarLeidas(int usuarioId) async {
    await DatabaseHelper.instance.marcarNotificacionesLeidas(usuarioId);
    noLeidas.value = 0;
  }

  static IconData icono(String tipo) {
    switch (tipo) {
      case 'seguridad':
        return Icons.shield_rounded;
      case 'compras':
        return Icons.shopping_bag_rounded;
      case 'promociones':
        return Icons.local_offer_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }
}
