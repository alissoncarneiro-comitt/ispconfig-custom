#!/bin/bash
set -e

echo "🖥️ Configurando hostname e /etc/hosts..."
echo "srv" > /etc/hostname
hostnamectl set-hostname srv

cat <<EOF > /etc/hosts
127.0.0.1       localhost
45.126.210.82   srv.comitt.com.br   srv
::1             ip6-localhost ip6-loopback
EOF

echo "📦 Instalando pacotes base..."
apt update
apt install -y \
  zstd lz4 jq net-tools sysstat \
  htop iotop iftop ncdu \
  git \
  auditd libpam-google-authenticator \
  curl sudo wget gnupg build-essential ca-certificates \
  git lsb-release \
  wireguard-tools

echo "✅ Base do sistema preparada."
