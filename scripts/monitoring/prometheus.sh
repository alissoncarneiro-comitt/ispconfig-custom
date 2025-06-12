#!/bin/bash
set -euo pipefail

echo " Instalando Prometheus..."
useradd --no-create-home --shell /bin/false prometheus || true
mkdir -p /etc/prometheus /var/lib/prometheus

cd /tmp
curl -LO https://github.com/prometheus/prometheus/releases/download/v2.48.1/prometheus-2.48.1.linux-amd64.tar.gz
tar xvf prometheus-2.48.1.linux-amd64.tar.gz
cd prometheus-2.48.1.linux-amd64

cp prometheus promtool /usr/local/bin/
cp -r consoles/ console_libraries/ /etc/prometheus/

cat <<EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']
  - job_name: 'php'
    static_configs:
      - targets: ['localhost:9253']
  - job_name: 'mariadb'
    static_configs:
      - targets: ['localhost:9104']
EOF

cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network-online.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus
