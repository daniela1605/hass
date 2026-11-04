import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../services/usuario_service.dart';

class UsuarioController extends ChangeNotifier {
  final UsuarioService _usuarioService = UsuarioService();

  List<Usuario> _usuarios = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  List<Usuario> get usuarios => _usuarios;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  // Cargar lista de usuarios
  Future<void> cargarUsuarios() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _usuarios = await _usuarioService.listarUsuarios();
    } catch (e) {
      _errorMessage = 'Error al cargar usuarios: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Registrar un nuevo usuario
  Future<bool> registrarUsuario({
    required String nombres,
    required String apellidoPaterno,
    String apellidoMaterno = '',
    required String email,
    required String password,
    required String rol,
    String username = '',
    String telefono = '',
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final nuevoUsuario = Usuario.conNombre(
        nombres: nombres,
        apellidoPaterno: apellidoPaterno,
        apellidoMaterno: apellidoMaterno,
        email: email,
        username: username,
        password: '',
        rol: rol,
        telefono: telefono,
      );

      await _usuarioService.registrarUsuario(nuevoUsuario, password);
      _successMessage = '¡Usuario "${nuevoUsuario.nombre}" registrado con éxito!';
      await cargarUsuarios();
      return true;
    } catch (e) {
      // Remover "Exception: " si viene en el mensaje
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Eliminar usuario
  Future<void> eliminarUsuario(int id) async {
    try {
      await _usuarioService.eliminarUsuario(id);
      await cargarUsuarios();
    } catch (e) {
      _errorMessage = 'No se pudo eliminar el usuario: ${e.toString()}';
      notifyListeners();
    }
  }

  // Editar datos de un usuario (solo admin). Devuelve null o el mensaje de error.
  Future<String?> editarUsuario(
    int id, {
    required String nombres,
    required String apellidoPaterno,
    required String apellidoMaterno,
    required String email,
    required String username,
    required String telefono,
    required String rol,
  }) async {
    try {
      await _usuarioService.editarUsuario(id,
          nombres: nombres,
          apellidoPaterno: apellidoPaterno,
          apellidoMaterno: apellidoMaterno,
          email: email,
          username: username,
          telefono: telefono,
          rol: rol);
      _successMessage =
          'Datos de "${Usuario.componerNombre(nombres, apellidoPaterno, apellidoMaterno)}" actualizados.';
      await cargarUsuarios();
      return null;
    } catch (e) {
      return e.toString().replaceAll('Exception: ', '');
    }
  }

  Future<void> desbloquearUsuario(int id) async {
    await _usuarioService.desbloquear(id);
    await cargarUsuarios();
  }

  // Cambiar rol de usuario (solo admin)
  Future<bool> cambiarRol(int id, String nuevoRol) async {
    try {
      await _usuarioService.actualizarRol(id, nuevoRol);
      _successMessage = 'Rol actualizado a "$nuevoRol" con éxito.';
      await cargarUsuarios();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void limpiarMensajes() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }
}
