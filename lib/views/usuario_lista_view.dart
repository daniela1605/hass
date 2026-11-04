import 'package:flutter/material.dart';
import '../controllers/usuario_controller.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import 'home_view.dart';
import 'notificaciones_view.dart';
import 'editar_usuario_view.dart';
import 'usuario_form_view.dart';

class UsuarioListaView extends StatefulWidget {
  final UsuarioController controller;
  final VoidCallback? onLogout;

  const UsuarioListaView({super.key, required this.controller, this.onLogout});

  @override
  State<UsuarioListaView> createState() => _UsuarioListaViewState();
}

class _UsuarioListaViewState extends State<UsuarioListaView> {
  @override
  void initState() {
    super.initState();
    // Cargar usuarios al iniciar la vista
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.cargarUsuarios();
    });
  }

  Widget _buildRolBadge(String rol) {
    Color bg;
    Color textColor;

    switch (rol.toLowerCase()) {
      case 'admin':
        bg = AppTheme.adminBg;
        textColor = AppTheme.adminText;
        break;
      case 'editor':
        bg = AppTheme.editorBg;
        textColor = AppTheme.editorText;
        break;
      case 'lector':
      default:
        bg = AppTheme.lectorBg;
        textColor = AppTheme.lectorText;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3), width: 1),
      ),
      child: Text(
        rol.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 11,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final usuarios = widget.controller.usuarios;
        final isLoading = widget.controller.isLoading;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBorderPink.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.security_rounded,
                    color: AppTheme.darkPink,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Usuarios'),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: AppTheme.darkPink),
                tooltip: 'Actualizar lista',
                onPressed: () => widget.controller.cargarUsuarios(),
              ),
              const NotificacionesBoton(),
              IconButton(
                icon: Icon(Icons.logout_rounded, color: AppTheme.darkPink),
                tooltip: 'Cerrar sesión',
                onPressed: () => cerrarSesion(context),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppTheme.darkPink,
            foregroundColor: Colors.white,
            elevation: 4,
            icon: const Icon(Icons.person_add_rounded),
            label: const Text(
              'Nuevo Usuario',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => UsuarioFormView(controller: widget.controller, esAdmin: true),
                ),
              );

              if (result == true && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF81C784),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.white),
                        SizedBox(width: 10),
                        Text(
                          '¡Usuario registrado exitosamente!',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              }
            },
          ),
          body: isLoading && usuarios.isEmpty
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.darkPink),
                )
              : RefreshIndicator(
                  color: AppTheme.darkPink,
                  backgroundColor: Colors.white,
                  onRefresh: () => widget.controller.cargarUsuarios(),
                  child: CustomScrollView(
                    slivers: [
                      // Cabecera decorativa rosita pastel
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFFF0F5),
                                  Color(0xFFFCE4EC),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppTheme.cardBorderPink,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Usuarios Registrados',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Gestión de cuentas y roles',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.cardBorderPink.withOpacity(0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '${usuarios.length} total',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.darkPink,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Lista de usuarios o mensaje vacío
                      if (usuarios.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppTheme.cardBorderPink,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.group_off_rounded,
                                      size: 56,
                                      color: AppTheme.primaryPink,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  const Text(
                                    'No hay usuarios registrados',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Comienza agregando uno con el botón rosado de abajo.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final u = usuarios[index];
                                return _buildUsuarioCard(u);
                              },
                              childCount: usuarios.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Future<void> _editarUsuario(Usuario u) async {
    final guardado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditarUsuarioView(usuario: u, controller: widget.controller),
      ),
    );
    if (guardado == true && mounted) {
      mostrarMensaje(context, '🌸 Datos de "${u.nombre}" actualizados');
    }
  }

  Widget _buildUsuarioCard(Usuario u) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _editarUsuario(u),
        onLongPress: () => _mostrarEditarRol(u), // atajo: cambiar rol
        child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar con inicial y ID
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF8BBD0), Color(0xFFF48FB1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  u.nombre.isNotEmpty ? u.nombre[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Información del usuario
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.softPinkBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'ID #${u.id ?? "-"}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          u.nombre,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.alternate_email_rounded,
                        size: 14,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '@${u.username} · ${u.email}',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _buildRolBadge(u.rol),
                      if (u.estaBloqueado)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('🔒 BLOQUEADA',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Botón editar datos (admin)
            IconButton(
              icon: Icon(
                Icons.edit_rounded,
                color: AppTheme.darkPink,
                size: 22,
              ),
              tooltip: 'Editar usuario',
              onPressed: () => _editarUsuario(u),
            ),

            // Botón eliminar
            IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                color: Colors.red.shade300,
                size: 22,
              ),
              tooltip: 'Eliminar usuario',
              onPressed: () => _confirmarEliminar(u),
            ),
          ],
        ),
      ),
      ),
    );
  }


  bool _esYo(Usuario u) {
    if (u.id == Sesion.instance.usuario?.id) {
      mostrarMensaje(context, 'No puedes eliminar ni cambiar el rol de tu propia cuenta.', error: true);
      return true;
    }
    return false;
  }

  void _confirmarEliminar(Usuario u) {
    if (u.id == null || _esYo(u)) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTheme.cardBorderPink),
        ),
        title: const Text(
          'Eliminar Usuario',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        content: Text(
          '¿Deseas eliminar a "${u.nombre}" de la base de datos?',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              widget.controller.eliminarUsuario(u.id!);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _mostrarEditarRol(Usuario u) {
    if (u.id == null || _esYo(u)) return;
    String rolSeleccionado = u.rol;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppTheme.cardBorderPink),
          ),
          title: Row(
            children: [
              Icon(Icons.manage_accounts_rounded, color: AppTheme.darkPink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Editar Rol de ${u.nombre}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cambia el tipo de usuario para:',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              Text(
                u.email,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.darkPink),
              ),
              const SizedBox(height: 14),
              _buildRolOption('admin', 'Administrador', 'Control total: usuarios y productos', Icons.admin_panel_settings_rounded, rolSeleccionado, (val) {
                setModalState(() => rolSeleccionado = val);
              }),
              const SizedBox(height: 8),
              _buildRolOption('editor', 'Editor', 'Solo agrega y elimina productos', Icons.edit_note_rounded, rolSeleccionado, (val) {
                setModalState(() => rolSeleccionado = val);
              }),
              const SizedBox(height: 8),
              _buildRolOption('lector', 'Lector (Comprador)', 'Solo consulta productos y compra', Icons.shopping_bag_outlined, rolSeleccionado, (val) {
                setModalState(() => rolSeleccionado = val);
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.darkPink,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await widget.controller.cambiarRol(u.id!, rolSeleccionado);
                if (ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('🌸 Rol de "${u.nombre}" cambiado a "$rolSeleccionado"'),
                      backgroundColor: const Color(0xFF81C784),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRolOption(String id, String titulo, String desc, IconData icono, String actual, Function(String) onSelect) {
    final seleccionado = id == actual;
    return InkWell(
      onTap: () => onSelect(id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: seleccionado ? AppTheme.cardBorderPink.withOpacity(0.3) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: seleccionado ? AppTheme.darkPink : Colors.grey.shade300,
            width: seleccionado ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icono, color: seleccionado ? AppTheme.darkPink : Colors.grey.shade600, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: seleccionado ? AppTheme.darkPink : AppTheme.textDark)),
                  Text(desc, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Radio<String>(
              value: id,
              groupValue: actual,
              activeColor: AppTheme.darkPink,
              onChanged: (val) {
                if (val != null) onSelect(val);
              },
            ),
          ],
        ),
      ),
    );
  }
}

