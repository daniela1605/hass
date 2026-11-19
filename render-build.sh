#!/usr/bin/env bash
set -e

echo "=== Instalando Flutter SDK para Render ==="
if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi

export PATH="$HOME/flutter/bin:$PATH"

flutter --version
flutter config --enable-web

echo "=== Instalando dependencias del proyecto ==="
flutter pub get

echo "=== Compilando aplicacion Flutter Web ==="
flutter build web --release --no-tree-shake-icons

echo "=== Build completado exitosamente en build/web ==="
