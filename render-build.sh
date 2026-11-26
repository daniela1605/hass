#!/usr/bin/env bash
set -e

echo "=== Instalando Flutter SDK para Render ==="
if [ ! -x "$HOME/flutter/bin/flutter" ]; then
  rm -rf "$HOME/flutter"
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi

export PATH="$HOME/flutter/bin:$PATH"

flutter config --no-analytics
flutter --version
flutter config --enable-web

echo "=== Instalando dependencias del proyecto ==="
flutter pub get

echo "=== Compilando aplicacion Flutter Web ==="
flutter build web --release --no-tree-shake-icons

echo "=== Verificando build/web ==="
ls -la build/web

echo "=== Build completado exitosamente ==="
