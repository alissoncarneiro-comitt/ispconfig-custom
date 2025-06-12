#!/usr/bin/env bash
set -e

echo "🚀 Rodando ISPConfig autoinstaller com --skip-web e --skip-php..."

cd "$(dirname "$0")/../ispconfig-autoinstaller"

sudo ./ispc3-ai.sh \
  --use-nginx \
  --skip-web \
  --skip-php \
  --channel=stable \
  --i-know-what-i-am-doing

echo "🔧 Aplicando templates customizados..."
cd ..
sudo ./scripts/install-templates.sh
