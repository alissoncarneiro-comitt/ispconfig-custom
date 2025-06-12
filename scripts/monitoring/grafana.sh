#!/bin/bash
set -euo pipefail

echo " Instalando Grafana..."
apt install -y apt-transport-https software-properties-common
curl -fsSL https://packages.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/grafana.gpg
add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
apt update
apt install -y grafana

systemctl enable grafana-server
systemctl start grafana-server

echo " Acesse o Grafana em http://<seu-ip>:3000 (admin / admin)"
