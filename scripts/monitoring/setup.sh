#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "📡 Iniciando instalação do stack de monitoramento Prometheus + Grafana + Exporters..."

bash "$DIR/prometheus.sh"
bash "$DIR/exporters/node_exporter.sh"
bash "$DIR/exporters/nginx_exporter.sh"
bash "$DIR/exporters/php_fpm_exporter.sh"
bash "$DIR/exporters/mysqld_exporter.sh"
bash "$DIR/grafana.sh"

echo " Stack de monitoramento instalado com sucesso!"