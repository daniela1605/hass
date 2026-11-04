# Configuración y credenciales

Las contraseñas **no** están en el código. Se leen al compilar desde `config/env.json`.

| Archivo | ¿Se sube a git? | Para qué |
|---|---|---|
| `env.example.json` | Sí | Plantilla con todas las claves (sin secretos) |
| `env.json` | **No** (está en `.gitignore`) | Tus valores reales |

## Configurar

1. Abre `config/env.json` y llena los valores (si no existe, copia `env.example.json`).
2. Ejecuta la app:
   - **VS Code:** F5 (ya está configurado en `.vscode/launch.json`).
   - **Terminal:** `flutter run --dart-define-from-file=config/env.json`
   - **APK:** `flutter build apk --dart-define-from-file=config/env.json`
   - **Android Studio:** Run → Edit Configurations → *Additional run args*:
     `--dart-define-from-file=config/env.json`

Si cambias `env.json`, vuelve a ejecutar la app (un *hot reload* no basta).

## Claves

| Clave | Descripción |
|---|---|
| `SMTP_USUARIO` | Correo Gmail que envía los códigos |
| `SMTP_PASSWORD` | Contraseña de aplicación de Gmail (https://myaccount.google.com/apppasswords) |
| `SMTP_REMITENTE` | Nombre que aparece como remitente |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_NUMERO` | SMS reales (opcional) |
| `APP_NAME`, `PRODUCTOS_API_URL`, `LADA_POR_DEFECTO` | Ajustes generales |

Si el correo o el SMS quedan vacíos, la app funciona en **modo demostración**:
los códigos se muestran en pantalla.

## Diferentes ambientes

Puedes tener varios archivos, por ejemplo `env.dev.json` y `env.prod.json`, y elegir
cuál usar con `--dart-define-from-file=config/env.prod.json`.

> ⚠️ Nota de seguridad: los valores quedan dentro del APK compilado. Esto evita
> subirlos a git, pero no los oculta de alguien que descompile la app. Para
> producción real, el envío de correos/SMS debería hacerlo un servidor propio.
