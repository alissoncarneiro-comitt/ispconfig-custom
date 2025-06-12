#!/usr/bin/env bash
set -euo pipefail
source env.sh

# Local padrão do config
mkdir -p "${HOME}/.config/rclone"
default_config="${HOME}/.config/rclone/rclone.conf"
config_file="${RCLONE_CONFIG:-$default_config}"

echo "➤ Checando configuração do rclone..."
if [[ ! -s "$config_file" ]]; then
  echo "⚠️ Arquivo de configuração do rclone não encontrado em $config_file"
  echo "Iniciando wizard interativo do rclone..."
  rclone config
fi

# Recheca após possível configuração
if [[ ! -s "$config_file" ]]; then
  echo "❌ Ainda não há configuração válida de rclone. Abortar."
  exit 1
fi

echo "➤ Verificando remote '${GDRIVE_REMOTE_NAME}'..."
remotes=$(rclone --config "$config_file" listremotes)
if ! grep -qE "^${GDRIVE_REMOTE_NAME}:" <<<"$remotes"; then
  echo "⚠️ Remoto '${GDRIVE_REMOTE_NAME}' inexistente."
  echo "Iniciando wizard interativo para criar remote '${GDRIVE_REMOTE_NAME}'..."
  rclone config
  # rechecagem
  remotes=$(rclone --config "$config_file" listremotes)
  if ! grep -qE "^${GDRIVE_REMOTE_NAME}:" <<<"$remotes"; then
    echo "❌ Remote '${GDRIVE_REMOTE_NAME}' ainda não configurado. Abortando."
    exit 1
  fi
fi

# Cria pasta de backup local
mkdir -p "$GDRIVE_BACKUP_FOLDER"

echo "✅ rclone configurado e remote '${GDRIVE_REMOTE_NAME}' disponível."



echo "Instalando backup cron GDrive..."
mkdir -p /opt/ispconfig-backup

    cat > "$BACKUP_SCRIPT" <<'EOS'
#!/bin/bash
set -e
BACKUP_DIR="/var/backup"
DEST="${GDRIVE_REMOTE_NAME}:ispconfig/$(date +%Y-%m-%d)"
echo "Enviando backups para $DEST"
rclone copy $BACKUP_DIR $DEST --progress --create-empty-src-dirs
EOS
    chmod 700 "$BACKUP_SCRIPT"
    chown root:root "$BACKUP_SCRIPT"

    echo "0 3 * * * root $BACKUP_SCRIPT >> /var/log/ispconfig-gdrive-backup.log 2>&1" > /etc/cron.d/ispconfig-gdrive

    cat > /etc/logrotate.d/ispconfig-gdrive <<'EOF'
/var/log/ispconfig-gdrive-backup.log {
    rotate 7
    daily
    missingok
    notifempty
    compress
    delaycompress
}
EOF
echo "Backup configurado."