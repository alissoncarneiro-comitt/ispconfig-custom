#!/bin/bash
set -e
set -o pipefail

export DEBIAN_FRONTEND=noninteractive
INSTALL_IONCUBE=${INSTALL_IONCUBE:-no}

# Se quiser instalar Blackfire, exporte estas variáveis:
# export BLACKFIRE_SERVER_ID=...
# export BLACKFIRE_SERVER_TOKEN=...

PHP_VERSIONS=(8.2 8.3 8.4)
EXTENSIONS_COMMON=(bcmath gmp intl gd mbstring xml soap zip curl fileinfo opcache cli common)
EXTENSIONS_DB=(mysql pgsql sqlite3)
EXTENSIONS_CACHE=(redis memcached)
EXTENSIONS_OTHER=(fpm yaml)
PECL_EXTENSIONS=(xdebug swoole rdkafka mongodb apcu newrelic)
INI_DIR="/etc/php"

echo "🧹 Removendo versões antigas de PHP..."

for version in "${PHP_VERSIONS[@]}"; do
    echo "  ↪ Limpando PHP $version"
    systemctl stop php${version}-fpm || true
    apt purge -y "php${version}" "php${version}-*" || true
    rm -rf "/etc/php/${version}"
    rm -rf "/usr/lib/php/${version}"
    rm -f "/etc/apt/sources.list.d/php-sury.list"
    update-alternatives --remove-all php || true
    update-alternatives --remove-all phpize || true
    update-alternatives --remove-all php-config || true
done

rm -rf /var/log/php
mkdir -p /var/log/php
chown www-data: /var/log/php


calculate_children() {
    local mem
    mem=$(free -m | awk '/Mem:/ {print $2}')
    echo $(( mem / 100 ))
}

echo "➤ Instalando dependências base..."
apt update
apt install -y --no-install-recommends \
    gettext-base \
    software-properties-common curl lsb-release ca-certificates gnupg apt-transport-https \
    build-essential pkg-config unzip autoconf automake libtool libssl-dev cmake git \
    libpcre3-dev libcurl4-openssl-dev libzip-dev zlib1g-dev libyaml-dev libonig-dev \
    libgmp-dev libicu-dev libjpeg-dev libpng-dev libwebp-dev libfreetype6-dev \
    libkrb5-dev libxml2-dev libmemcached-dev libevent-dev librdkafka-dev libsasl2-dev \
    libprotobuf-dev protobuf-compiler \
    libsqlite3-dev libbrotli-dev libc-ares-dev \
    php-pear php-igbinary php-msgpack

add_sury_repo_if_needed() {
    if ! grep -q "packages.sury.org" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        echo "➤ Adicionando repositório SURY (PHP)..."
        apt install -y --no-install-recommends gnupg lsb-release curl ca-certificates apt-transport-https
        curl -fsSL https://packages.sury.org/php/apt.gpg \
            | gpg --dearmor -o /etc/apt/trusted.gpg.d/php.gpg
        echo "deb https://packages.sury.org/php $(lsb_release -cs) main" \
            > /etc/apt/sources.list.d/php-sury.list
        apt update
    else
        echo "✅ SURY já configurado"
    fi
}
add_sury_repo_if_needed

echo "➤ Instalando php-dev para compilação de PECL..."
for v in "${PHP_VERSIONS[@]}"; do
    apt install -y --no-install-recommends php${v}-dev
done

for version in "${PHP_VERSIONS[@]}"; do
    echo "⦿ Instalando PHP $version + extensões APT..."

    PACKAGES=()
    for ext in "${EXTENSIONS_COMMON[@]}" "${EXTENSIONS_OTHER[@]}"; do
        [[ "$ext" == "imagick" ]] && continue
        PACKAGES+=("php${version}-$ext")
    done
    for ext in "${EXTENSIONS_DB[@]}" "${EXTENSIONS_CACHE[@]}"; do
        PACKAGES+=("php${version}-$ext")
    done
    PACKAGES+=("php-imagick" "php${version}-grpc")
    apt install -y --no-install-recommends "${PACKAGES[@]}" || {
        echo "⚠️ Falha ao instalar alguns pacotes APT para PHP $version, continuando..."
    }

    echo "⦿ Configurando alternativas para PHP $version..."
    update-alternatives --install /usr/bin/php php /usr/bin/php${version} ${version//./}
    update-alternatives --install /usr/bin/phpize phpize /usr/bin/phpize${version} ${version//./}
    update-alternatives --install /usr/bin/php-config php-config /usr/bin/php-config${version} ${version//./}

    echo "⦿ Ajustando php.ini para PHP $version..."
    PHP_INI_FPM="${INI_DIR}/${version}/fpm/php.ini"
    PHP_INI_CLI="${INI_DIR}/${version}/cli/php.ini"
    for PHP_INI in "$PHP_INI_FPM" "$PHP_INI_CLI"; do
        [ -f "$PHP_INI" ] || continue
        sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "$PHP_INI"
        sed -i 's/^post_max_size = .*/post_max_size = 100M/' "$PHP_INI"
        sed -i 's/^max_execution_time = .*/max_execution_time = 60/' "$PHP_INI"
        sed -i 's~^;?date.timezone =.*~date.timezone = America/Sao_Paulo~' "$PHP_INI"
        sed -i 's/^;?expose_php = .*/expose_php = Off/' "$PHP_INI"
        sed -i 's/^;?display_errors = .*/display_errors = Off/' "$PHP_INI"
        sed -i 's/^;?log_errors = .*/log_errors = On/' "$PHP_INI"
        sed -i "s~^;?error_log = .*~error_log = /var/log/php/php${version}-fpm.log~" "$PHP_INI"
        cat << EOF >> "$PHP_INI"

[opcache]
opcache.enable=1
opcache.memory_consumption=256
opcache.max_accelerated_files=100000
opcache.interned_strings_buffer=16
opcache.jit=1255
opcache.jit_buffer_size=64M
EOF
    done

    echo "⦿ Verificando e limpando configurações duplicadas apenas para extensões PECL para PHP $version..."
    for ext in "${PECL_EXTENSIONS[@]}"; do
        if [ -f "${INI_DIR}/${version}/mods-available/${ext}.ini" ]; then
            echo "   ℹ️ Removendo configuração existente para $ext..."
            rm -f "${INI_DIR}/${version}/mods-available/${ext}.ini"
            rm -f "${INI_DIR}/${version}/cli/conf.d/20-${ext}.ini"
            rm -f "${INI_DIR}/${version}/fpm/conf.d/20-${ext}.ini"
        fi
        for PHP_INI in "$PHP_INI_FPM" "$PHP_INI_CLI"; do
            [ -f "$PHP_INI" ] && sed -i "/^extension=${ext}\\.so/d" "$PHP_INI"
            [ -f "$PHP_INI" ] && sed -i "/^extension=$ext/d" "$PHP_INI"
        done
    done

    echo "⦿ Instalando extensões PECL para PHP $version..."
    export MAKEFLAGS="-j$(nproc)"
    for ext in "${PECL_EXTENSIONS[@]}"; do
        echo "   ➤ $ext"
        if php${version} -m 2>/dev/null | grep -qi "^${ext}$"; then
            echo "   ℹ️ $ext já instalado para PHP $version, pulando..."
            continue
        fi
        if apt list --installed 2>/dev/null | grep -q "php${version}-${ext}/"; then
            echo "   ℹ️ $ext já instalado via APT para PHP $version, pulando..."
            continue
        fi
        if [[ "$ext" == "apcu" ]]; then
            pecl install -f apcu
            echo "extension=apcu.so" > "${INI_DIR}/${version}/mods-available/apcu.ini"
            phpenmod -v "$version" apcu || true
            echo "   ✅ apcu habilitado"
            continue
        elif [[ "$ext" == "xdebug" ]]; then
            echo "   🔁 Resetando xdebug antes da instalação"
            phpdismod -v "$version" xdebug || true
            rm -f "${INI_DIR}/${version}/mods-available/xdebug.ini"
            rm -f "${INI_DIR}/${version}/cli/conf.d/20-xdebug.ini"
            rm -f "${INI_DIR}/${version}/fpm/conf.d/20-xdebug.ini"

            pecl install -f xdebug
            EXT_DIR="$(php-config${version} --extension-dir)"
            SO_FILE="$(find "$EXT_DIR" -maxdepth 1 -type f -name "${ext}*.so" | head -n1)"
            if [[ -n "$SO_FILE" ]]; then
                SO_BASENAME="$(basename "$SO_FILE")"
                echo "zend_extension=$SO_BASENAME" > "${INI_DIR}/${version}/mods-available/xdebug.ini"
                phpenmod -v "$version" xdebug || true
                echo "   ✅ xdebug habilitado como zend_extension"
            else
                echo "   ⚠️ xdebug não foi encontrado/carregado"
            fi
            continue
        else
            pecl install -f "$ext" || { echo "   ⚠️ falha no PECL/$ext"; continue; }
        fi
        EXT_DIR="$(php-config${version} --extension-dir)"
        SO_FILE="$(find "$EXT_DIR" -maxdepth 1 -type f -name "${ext}*.so" | head -n1)"
        if [[ -n "$SO_FILE" ]]; then
            SO_BASENAME="$(basename "$SO_FILE")"
            echo "extension=$SO_BASENAME" > "${INI_DIR}/${version}/mods-available/${ext}.ini"
            phpenmod -v "$version" "$ext" || true
            echo "   ✅ $ext habilitado como $SO_BASENAME"
        else
            if php${version} -d extension_dir="$EXT_DIR" -m 2>/dev/null | grep -qi "^$ext$"; then
                echo "   ℹ️ $ext já ativo via autodetect"
            else
                echo "   ⚠️ $ext não foi encontrado/carregado"
            fi
        fi
    done

    if [ "$INSTALL_IONCUBE" = "yes" ]; then
        echo "⦿ Instalando ionCube Loader para PHP $version..."
        IONCUBE_DIR="/opt/ioncube"
        mkdir -p "$IONCUBE_DIR"
        curl -fsSL https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz -o /tmp/ioncube.tar.gz
        tar -xzf /tmp/ioncube.tar.gz -C /opt
        cp "${IONCUBE_DIR}/ioncube/ioncube_loader_lin_${version}.so" "$(php-config${version} --extension-dir)/"
        echo "zend_extension=ioncube_loader_lin_${version}.so" > "${INI_DIR}/${version}/mods-available/ioncube.ini"
        phpenmod -v "$version" ioncube
    fi

    echo "⦿ Desativando o pool default www.conf para PHP $version..."
    WWW_CONF="/etc/php/${version}/fpm/pool.d/www.conf"
    if [ -f "$WWW_CONF" ]; then
        mv "$WWW_CONF" "${WWW_CONF}.disabled"
        echo "   ✅ Pool padrão www.conf desativado"
    fi

    echo "⦿ Gerando pool ISPConfig para PHP $version..."
    children=$(calculate_children)
    export PHP_VERSION="$version"
    export MAX_CHILDREN="$children"
    export MAX_SPARE="$(( children / 2 ))"
    envsubst '${PHP_VERSION} ${MAX_CHILDREN} ${MAX_SPARE}' \
    < "./php/pools.d/ispconfig.conf.template" \
    > /etc/php/${version}/fpm/pool.d/ispconfig-${version}.conf
    

    mkdir -p /var/log/php
    chown www-data: /var/log/php
    if command -v systemctl >/dev/null 2>&1 && pidof systemd >/dev/null 2>&1; then
        systemctl restart php${version}-fpm || true
    elif command -v service >/dev/null 2>&1; then
        service php${version}-fpm restart || true
    else
        echo "ℹ️ Reinicie php${version}-fpm manualmente."
    fi
done

echo "➤ Limpando pacotes de compilação..."
apt purge -y build-essential pkg-config unzip autoconf automake libtool git cmake
apt autoremove -y --purge && apt clean

echo "✅ PHP-FPM multi-versão + ISPConfig + PECL instalado com sucesso!"