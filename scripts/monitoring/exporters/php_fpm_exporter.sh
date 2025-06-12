#!/bin/bash
set -euo pipefail

echo " Instalando Exporter para PHP-FPM..."
cd /tmp
curl -LO https://github.com/hipages/php-fpm_exporter/releases/download/v2.8.0/php-fpm_exporter_2.8.0_linux_amd64.tar.gz
tar xvf php-fpm_exporter_2.8.0_linux_amd64.tar.gz
cp php-fpm_exporter /usr/local/bin/

cat <<EOF > /etc/systemd/system/php-fpm_exporter.service
[Unit]
Description=PHP-FPM Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/php-fpm_exporter --phpfpm.scrape-uri tcp://127.0.0.1:9000/status
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable php-fpm_exporter
systemctl start php-fpm_exporter
