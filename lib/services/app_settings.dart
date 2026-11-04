import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Paleta de colores seleccionable por el usuario.
class Paleta {
  final String id;
  final String nombre;
  final Color primario; // tono pastel
  final Color acento; // botones / títulos
  final Color fondo;
  final Color borde;

  const Paleta(this.id, this.nombre, this.primario, this.acento, this.fondo, this.borde);

  static const rosa = Paleta('rosa', 'Rosa', Color(0xFFF48FB1), Color(0xFFEC407A), Color(0xFFFFF2F5), Color(0xFFF8BBD0));
  static const lavanda = Paleta('lavanda', 'Lavanda', Color(0xFFB39DDB), Color(0xFF7E57C2), Color(0xFFF6F1FB), Color(0xFFD1C4E9));
  static const menta = Paleta('menta', 'Menta', Color(0xFF80CBC4), Color(0xFF00897B), Color(0xFFEFF8F6), Color(0xFFB2DFDB));
  static const durazno = Paleta('durazno', 'Durazno', Color(0xFFFFAB91), Color(0xFFF4511E), Color(0xFFFFF5F0), Color(0xFFFFCCBC));
  static const cielo = Paleta('cielo', 'Cielo', Color(0xFF90CAF9), Color(0xFF1E88E5), Color(0xFFF0F7FF), Color(0xFFBBDEFB));

  static const todas = [rosa, lavanda, menta, durazno, cielo];

  static Paleta porId(String? id) =>
      todas.firstWhere((p) => p.id == id, orElse: () => rosa);
}

/// Preferencias personalizadas del usuario (tema, texto, notificaciones,
/// biometría). Se guardan en SharedPreferences.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  late SharedPreferences _prefs;

  Paleta _paleta = Paleta.rosa;
  double _escalaTexto = 1.0;
  bool _notifSeguridad = true;
  bool _notifCompras = true;
  bool _notifPromociones = true;
  int? _biometriaUsuarioId;
  String _canal2fa = 'email';

  Paleta get paleta => _paleta;
  double get escalaTexto => _escalaTexto;
  bool get notifSeguridad => _notifSeguridad;
  bool get notifCompras => _notifCompras;
  bool get notifPromociones => _notifPromociones;
  int? get biometriaUsuarioId => _biometriaUsuarioId;
  String get canal2fa => _canal2fa;

  Future<void> cargar() async {
    _prefs = await SharedPreferences.getInstance();
    _paleta = Paleta.porId(_prefs.getString('cfg_paleta'));
    _escalaTexto = _prefs.getDouble('cfg_escala_texto') ?? 1.0;
    _notifSeguridad = _prefs.getBool('cfg_notif_seguridad') ?? true;
    _notifCompras = _prefs.getBool('cfg_notif_compras') ?? true;
    _notifPromociones = _prefs.getBool('cfg_notif_promos') ?? true;
    _biometriaUsuarioId = _prefs.getInt('cfg_bio_usuario');
    _canal2fa = _prefs.getString('cfg_canal_2fa') ?? 'email';
  }

  Future<void> setPaleta(Paleta p) async {
    _paleta = p;
    await _prefs.setString('cfg_paleta', p.id);
    notifyListeners();
  }

  Future<void> setEscalaTexto(double v) async {
    _escalaTexto = v;
    await _prefs.setDouble('cfg_escala_texto', v);
    notifyListeners();
  }

  Future<void> setNotifSeguridad(bool v) async {
    _notifSeguridad = v;
    await _prefs.setBool('cfg_notif_seguridad', v);
    notifyListeners();
  }

  Future<void> setNotifCompras(bool v) async {
    _notifCompras = v;
    await _prefs.setBool('cfg_notif_compras', v);
    notifyListeners();
  }

  Future<void> setNotifPromociones(bool v) async {
    _notifPromociones = v;
    await _prefs.setBool('cfg_notif_promos', v);
    notifyListeners();
  }

  Future<void> setCanal2fa(String canal) async {
    _canal2fa = canal;
    await _prefs.setString('cfg_canal_2fa', canal);
    notifyListeners();
  }

  Future<void> setBiometriaUsuario(int? usuarioId) async {
    _biometriaUsuarioId = usuarioId;
    if (usuarioId == null) {
      await _prefs.remove('cfg_bio_usuario');
    } else {
      await _prefs.setInt('cfg_bio_usuario', usuarioId);
    }
    notifyListeners();
  }

  /// ¿Se debe mostrar una notificación de este tipo?
  bool permite(String tipo) {
    switch (tipo) {
      case 'seguridad':
        return _notifSeguridad;
      case 'compras':
        return _notifCompras;
      case 'promociones':
        return _notifPromociones;
      default:
        return true;
    }
  }
}
