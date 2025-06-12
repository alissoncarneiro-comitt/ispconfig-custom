#!/usr/bin/env bash
set -e

BASE=$(dirname "$0")/..
CONF_DIR="/usr/local/ispconfig/server/conf"

echo "🔧 Aplicando templates customizados..."
cp "$BASE/templates/nginx_template/custom_tpl.php" "$CONF_DIR/nginx_vhost.conf.master"
cp "$BASE/templates/php_fpm_pool/custom_pool.conf.master" "$CONF_DIR/php_fpm_pool.conf.master"
echo "✅ Templates aplicados com sucesso!"
