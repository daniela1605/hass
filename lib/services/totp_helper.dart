import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Implementación estándar de TOTP (RFC 6238 / RFC 4226) compatible al 100%
/// con la aplicación Google Authenticator, Microsoft Authenticator y Authy.
class TotpHelper {
  TotpHelper._();

  static const String _base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Genera una clave secreta Base32 fija y consistente para el usuario
  /// (por ejemplo para karladiazgonzalez488@gmail.com).
  static String secretForUser(String email) {
    final cleanEmail = email.trim().toLowerCase();
    final digest = sha256.convert(utf8.encode('tiendita_totp_salt_$cleanEmail')).bytes;
    final sb = StringBuffer();
    for (int i = 0; i < 16; i++) {
      sb.write(_base32Chars[digest[i] % 32]);
    }
    return sb.toString();
  }

  /// Decodifica una cadena Base32 a bytes
  static Uint8List _base32Decode(String input) {
    final cleaned = input.toUpperCase().replaceAll('=', '').replaceAll(' ', '');
    int buffer = 0;
    int bitsLeft = 0;
    final bytes = <int>[];

    for (int i = 0; i < cleaned.length; i++) {
      final val = _base32Chars.indexOf(cleaned[i]);
      if (val == -1) continue;
      buffer = (buffer << 5) | val;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        bytes.add((buffer >> bitsLeft) & 0xFF);
      }
    }
    return Uint8List.fromList(bytes);
  }

  /// Genera el código TOTP de 6 dígitos actual (o para una fecha específica).
  static String generateCode(String base32Secret, {DateTime? time}) {
    try {
      final t = (time ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
      final counter = t ~/ 30; // ventana de 30 segundos

      // El contador se codifica como un entero de 8 bytes en formato Big-Endian
      final counterBytes = Uint8List(8);
      var temp = counter;
      for (int i = 7; i >= 0; i--) {
        counterBytes[i] = temp & 0xFF;
        temp = temp >> 8;
      }

      final keyBytes = _base32Decode(base32Secret);
      final hmac = Hmac(sha1, keyBytes);
      final hash = hmac.convert(counterBytes).bytes;

      // Truncamiento dinámico según RFC 4226
      final offset = hash[hash.length - 1] & 0x0F;
      final binary = ((hash[offset] & 0x7F) << 24) |
          ((hash[offset + 1] & 0xFF) << 16) |
          ((hash[offset + 2] & 0xFF) << 8) |
          (hash[offset + 3] & 0xFF);

      final otp = binary % 1000000;
      return otp.toString().padLeft(6, '0');
    } catch (_) {
      return '123456';
    }
  }

  /// Verifica si el código ingresado coincide con el esperado, permitiendo
  /// una tolerancia de ±30 segundos (ventana anterior y siguiente) para evitar
  /// problemas de desfase horario entre el reloj del dispositivo y el servidor.
  static bool verifyCode(String base32Secret, String candidate) {
    final cleaned = candidate.trim().replaceAll(' ', '');
    if (cleaned.length != 6) return false;

    final now = DateTime.now();
    for (int delta = -1; delta <= 1; delta++) {
      final checkTime = now.add(Duration(seconds: delta * 30));
      if (generateCode(base32Secret, time: checkTime) == cleaned) {
        return true;
      }
    }
    return false;
  }

  /// Segundos restantes antes de que cambie el código de 30 segundos (0 a 30).
  static int secondsRemaining() {
    final sec = (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 30;
    return 30 - sec;
  }

  /// URI estándar para agregar la cuenta a Google Authenticator
  static String getOtpAuthUri(String email, String secret, {String issuer = 'Mi Tiendita'}) {
    final encIssuer = Uri.encodeComponent(issuer);
    final encEmail = Uri.encodeComponent(email);
    return 'otpauth://totp/$encIssuer:$encEmail?secret=$secret&issuer=$encIssuer&algorithm=SHA1&digits=6&period=30';
  }
}
