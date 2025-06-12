#!/bin/bash
set -euo pipefail

echo " Instalando Exporter para MariaDB..."
useradd -rs /bin/false mysqld_exporter || true

cd /tmp
curl -LO https://github.com/prometheus/mysqld_exporter/releases/download/v0.15.1/mysqld_exporter-0.15.1.linux-amd64.tar.gz
tar xvf mysqld_exporter-0.15.1.linux-amd64.tar.gz
cp mysqld_exporter-0.15.1.linux-amd64/mysqld_exporter /usr/local/bin/

mysql -uroot -proot <<EOF
CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY 'exporter_password';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
EOF

cat <<EOF > /etc/.mysqld_exporter.cnf
[client]
user=exporter
password=exporter_password
EOF

cat <<EOF > /etc/systemd/system/mysqld_exporter.service
[Unit]
Description=Prometheus MySQL Exporter
After=network.target

[Service]
User=mysqld_exporter
ExecStart=/usr/local/bin/mysqld_exporter --config.my-cnf="/etc/.mysqld_exporter.cnf"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mysqld_exporter
systemctl start mysqld_exporter
