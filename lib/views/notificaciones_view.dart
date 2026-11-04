import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../repository/database_helper.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// Campana con contador de no leídas (para los AppBar).
class NotificacionesBoton extends StatelessWidget {
  const NotificacionesBoton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.instance.noLeidas,
      builder: (context, n, _) => IconButton(
        tooltip: 'Notificaciones',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificacionesView()),
        ),
        icon: Badge(
          isLabelVisible: n > 0,
          label: Text(n > 99 ? '99+' : '$n'),
          backgroundColor: AppTheme.darkPink,
          child: Icon(Icons.notifications_rounded, color: AppTheme.darkPink),
        ),
      ),
    );
  }
}

/// Bandeja de notificaciones del usuario.
class NotificacionesView extends StatefulWidget {
  const NotificacionesView({super.key});

  @override
  State<NotificacionesView> createState() => _NotificacionesViewState();
}

class _NotificacionesViewState extends State<NotificacionesView> {
  List<Map<String, dynamic>> _items = [];
  bool _cargando = true;

  int get _usuarioId => Sesion.instance.usuario!.id!;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final data = await DatabaseHelper.instance.obtenerNotificaciones(_usuarioId);
    if (!mounted) return;
    setState(() {
      _items = data;
      _cargando = false;
    });
    await NotificationService.instance.marcarLeidas(_usuarioId);
  }

  Future<void> _borrarTodas() async {
    await DatabaseHelper.instance.eliminarNotificaciones(_usuarioId);
    NotificationService.instance.noLeidas.value = 0;
    if (mounted) setState(() => _items = []);
  }

  Color _color(String tipo) {
    switch (tipo) {
      case 'seguridad':
        return const Color(0xFFE57373);
      case 'compras':
        return const Color(0xFF81C784);
      case 'promociones':
        return const Color(0xFFFFB74D);
      default:
        return AppTheme.primaryPink;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔔 Notificaciones'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Borrar todas',
              icon: Icon(Icons.delete_sweep_rounded, color: AppTheme.darkPink),
              onPressed: _borrarTodas,
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 72, color: AppTheme.cardBorderPink),
                      const SizedBox(height: 12),
                      const Text('No tienes notificaciones', style: TextStyle(color: AppTheme.textMuted, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final n = _items[i];
                      final tipo = n['tipo'] as String? ?? 'sistema';
                      final fecha = DateTime.tryParse(n['fecha'] as String? ?? '') ?? DateTime.now();
                      final nueva = (n['leida'] as int? ?? 0) == 0;
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _color(tipo).withValues(alpha: 0.2),
                            child: Icon(NotificationService.icono(tipo), color: _color(tipo)),
                          ),
                          title: Text(n['titulo'] as String? ?? '',
                              style: TextStyle(
                                  fontWeight: nueva ? FontWeight.bold : FontWeight.w600,
                                  color: AppTheme.textDark)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(n['cuerpo'] as String? ?? ''),
                              const SizedBox(height: 4),
                              Text(DateFormat('dd/MM/yyyy HH:mm').format(fecha),
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                            ],
                          ),
                          trailing: nueva
                              ? Icon(Icons.circle, size: 10, color: AppTheme.darkPink)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
