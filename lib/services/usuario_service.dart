import '../models/usuario.dart';
import '../repository/database_helper.dart';
import 'security_service.dart';

class UsuarioService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  static final RegExp regexEmail = RegExp(r'^[\w\.\-+]+@([\w-]+\.)+[\w-]{2,}$');
  static final RegExp regexUsername = RegExp(r'^[a-zA-Z0-9._]{3,20}$');

  /// Letras (con acentos y ñ), espacios, apóstrofo, punto y guion.
  static final RegExp regexNombre = RegExp(r"^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ' .\-]+$");

  /// Valida una parte del nombre. Devuelve el error o `null`.
  static String? validarParteNombre(String? valor, String campo, {bool obligatorio = true}) {
    final v = (valor ?? '').trim();
    if (v.isEmpty) return obligatorio ? '$campo es obligatorio.' : null;
    if (v.length < 2) return '$campo debe tener al menos 2 letras.';
    if (v.length > 50) return '$campo no puede tener más de 50 caracteres.';
    if (!regexNombre.hasMatch(v)) return '$campo solo puede contener letras.';
    return null;
  }

  static String? _validarNombreCompleto(String nombres, String paterno, String materno) =>
      validarParteNombre(nombres, 'El nombre') ??
      validarParteNombre(paterno, 'El apellido paterno') ??
      validarParteNombre(materno, 'El apellido materno', obligatorio: false);

  // Consultar todos los usuarios
  Future<List<Usuario>> listarUsuarios() async {
    return await _dbHelper.obtenerTodos();
  }

  // Comprobar si el correo ya está registrado
  Future<bool> existeEmail(String email) async {
    final usuario = await _dbHelper.obtenerPorEmail(email);
    return usuario != null;
  }

  Future<bool> existeUsername(String username) => _dbHelper.existeUsername(username);

  /// Validaciones de negocio. Devuelve el mensaje de error o `null`.
  Future<String?> validarNuevo({
    required String nombres,
    required String apellidoPaterno,
    String apellidoMaterno = '',
    required String email,
    required String username,
    required String password,
    required String rol,
    String telefono = '',
  }) async {
    final errorNombre = _validarNombreCompleto(nombres, apellidoPaterno, apellidoMaterno);
    if (errorNombre != null) return errorNombre;
    if (email.trim().isEmpty) return 'El correo electrónico es obligatorio.';
    if (!regexEmail.hasMatch(email.trim())) return 'El formato del correo electrónico no es válido.';
    if (!regexUsername.hasMatch(username.trim())) {
      return 'El usuario debe tener 3-20 caracteres (letras, números, punto o guion bajo).';
    }
    if (telefono.trim().isNotEmpty &&
        telefono.replaceAll(RegExp(r'\D'), '').length < 10) {
      return 'El teléfono debe tener al menos 10 dígitos.';
    }
    if (!['admin', 'editor', 'lector'].contains(rol)) {
      return 'El rol debe ser admin, editor o lector.';
    }
    final errorPass = PoliticaRol.de(rol).validarPassword(password);
    if (errorPass != null) return errorPass;
    if (await existeEmail(email)) return 'El correo ya está registrado.';
    if (await existeUsername(username)) return 'Ese nombre de usuario ya está en uso.';
    return null;
  }

  // Registrar un nuevo usuario con validaciones de negocio
  Future<void> registrarUsuario(Usuario usuario, String passwordPlano) async {
    final error = await validarNuevo(
      nombres: usuario.nombres,
      apellidoPaterno: usuario.apellidoPaterno,
      apellidoMaterno: usuario.apellidoMaterno,
      email: usuario.email,
      username: usuario.username,
      password: passwordPlano,
      rol: usuario.rol,
      telefono: usuario.telefono,
    );
    if (error != null) throw Exception(error);

    final hash = await SecurityService.hashPassword(passwordPlano);
    await _dbHelper.insertar(usuario.copyWith(password: hash));
  }

  /// Valida y guarda la edición de un usuario existente.
  Future<void> editarUsuario(
    int id, {
    required String nombres,
    required String apellidoPaterno,
    required String apellidoMaterno,
    required String email,
    required String username,
    required String telefono,
    required String rol,
  }) async {
    final errorNombre = _validarNombreCompleto(nombres, apellidoPaterno, apellidoMaterno);
    if (errorNombre != null) throw Exception(errorNombre);
    if (!regexEmail.hasMatch(email.trim())) throw Exception('El formato del correo no es válido.');
    if (!regexUsername.hasMatch(username.trim())) {
      throw Exception('El usuario debe tener 3-20 caracteres (letras, números, punto o guion bajo).');
    }
    final digitos = telefono.replaceAll(RegExp(r'\D'), '');
    if (digitos.isNotEmpty && digitos.length < 10) {
      throw Exception('El teléfono debe tener al menos 10 dígitos.');
    }
    if (!['admin', 'editor', 'lector'].contains(rol)) {
      throw Exception('El rol debe ser admin, editor o lector.');
    }
    final porEmail = await _dbHelper.obtenerPorEmail(email);
    if (porEmail != null && porEmail.id != id) throw Exception('Ese correo ya pertenece a otra cuenta.');
    final porUsuario = await _dbHelper.obtenerPorUsername(username);
    if (porUsuario != null && porUsuario.id != id) throw Exception('Ese nombre de usuario ya está en uso.');

    await _dbHelper.actualizarDatosUsuario(id,
        nombres: nombres,
        apellidoPaterno: apellidoPaterno,
        apellidoMaterno: apellidoMaterno,
        email: email,
        username: username,
        telefono: telefono,
        rol: rol);
  }

  Future<void> desbloquear(int id) => _dbHelper.reiniciarIntentos(id);

  // Eliminar usuario
  Future<void> eliminarUsuario(int id) async {
    await _dbHelper.eliminar(id);
  }

  // Actualizar rol de usuario (solo admin)
  Future<void> actualizarRol(int id, String nuevoRol) async {
    if (!['admin', 'editor', 'lector'].contains(nuevoRol)) {
      throw Exception('El rol debe ser admin, editor o lector.');
    }
    await _dbHelper.actualizarRol(id, nuevoRol);
  }
}
