#!/bin/bash
set -euo pipefail

echo " Instalando Exporter para NGINX..."
cd /tmp
curl -LO https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v0.11.0/nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz
tar xvf nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz
cp nginx-prometheus-exporter /usr/local/bin/

cat <<EOF > /etc/systemd/system/nginx_exporter.service
[Unit]
Description=NGINX Prometheus Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/nginx-prometheus-exporter -nginx.scrape-uri http://localhost/nginx_status
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nginx_exporter
systemctl start nginx_exporter
