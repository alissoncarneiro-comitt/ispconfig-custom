#!/usr/bin/env bash
set -euo pipefail

# Configurações do Jail NGINX e desativa SSHD no Fail2Ban
echo "🛡️  Configurando Fail2Ban para NGINX req-limit..."

# Garante que os diretórios existem
mkdir -p /etc/fail2ban/jail.d /etc/fail2ban/filter.d

# Cria o jail customizado para limitar requisições NGINX
cat > /etc/fail2ban/jail.d/nginx-custom.conf <<'EOF'
[nginx-req-limit]
enabled = true
filter = nginx-req-limit
action = iptables-multiport[name=ReqLimit, port="http,https", protocol=tcp]
logpath = /var/log/nginx/*error.log
findtime = 600
bantime = 7200
maxretry = 10
EOF

# Cria o filtro correspondente
cat > /etc/fail2ban/filter.d/nginx-req-limit.conf <<'EOF'
[Definition]
failregex = limiting requests.*client: <HOST>
ignoreregex =
EOF

# Desativa o jail padrão de SSHD para evitar erro de log ausente
cat > /etc/fail2ban/jail.d/disable-sshd.conf <<'EOF'
[sshd]
enabled = false
EOF

# Garante que o serviço Fail2Ban esteja em execução
if command -v fail2ban-client >/dev/null 2>&1; then
    echo "➤ Iniciando ou verificando status do Fail2Ban..."
    fail2ban-client start 2>/dev/null || true
fi

# Recarrega as configurações do Fail2Ban de forma compatível
if command -v fail2ban-client >/dev/null 2>&1; then
    echo "➤ Recarregando Fail2Ban via client..."
    fail2ban-client reload || true
elif command -v service >/dev/null 2>&1; then
    echo "➤ Reiniciando Fail2Ban via service..."
    service fail2ban restart || true
else
    echo "ℹ️ Nenhum gerenciador de serviço detectado. Reinicie o Fail2Ban manualmente."
fi

echo "✅ Fail2Ban configurado e reiniciado!"
