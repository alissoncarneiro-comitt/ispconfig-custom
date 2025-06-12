#!/bin/bash
set -e
set -o pipefail
NGINX_VERSION="1.28.0"
OPENSSL_VERSION="openssl-3.3.1"
BUILD_DIR="/tmp/nginx-build"
export DEBIAN_FRONTEND=noninteractive

# Função para detectar número de núcleos
get_cores() {
    echo "$(nproc)"
}

# Função de log otimizada
log() {
    echo -e "\n[INFO] $1"
}

# Função de retry otimizada
retry() {
    local n=0 max_attempts=2 delay=1
    while [ $n -lt $max_attempts ]; do
        if "$@"; then return 0; fi
        n=$((n+1))
        sleep $delay
    done
    echo "[ERROR] Falha após $max_attempts tentativas: $*" >&2
    return 1
}

log "Iniciando build NGINX ${NGINX_VERSION} com NJS dinâmico..."

log "Detectando sistema operacional"
. /etc/os-release
DISTRO=$ID
VERSION=$VERSION_ID
CODENAME=$VERSION_CODENAME
echo "Distribuição: $DISTRO | Versão: $VERSION | Codinome: $CODENAME"

log "Configurando repositórios Debian"
rm -f /etc/apt/sources.list{,.d/*.list}
apt clean
cat > /etc/apt/sources.list <<EOF
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian $CODENAME main
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian $CODENAME-updates main
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://security.debian.org/debian-security $CODENAME-security main
EOF

log "Atualizando repositórios"
rm -rf /var/lib/apt/lists/*
apt update -q

log "Instalando dependências básicas"
BASIC_DEPS=(
    build-essential git wget curl unzip libtool automake autoconf cmake
    zlib1g-dev libpcre3-dev pkg-config libgd-dev ca-certificates uuid-dev
    libxml2-dev libxslt1-dev sudo
)
apt install -y --no-install-recommends "${BASIC_DEPS[@]}"

log "Verificando dependências opcionais"
OPTIONAL_DEPS=("libmaxminddb-dev" "libmaxminddb0" "libssl-dev")
for pkg in "${OPTIONAL_DEPS[@]}"; do
    apt-cache show "$pkg" >/dev/null 2>&1 && 
    apt install -y --no-install-recommends "$pkg" &
done
wait

# Verificação de serviço NGINX
NGINX_WAS_RUNNING=false
if systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl stop nginx
    NGINX_WAS_RUNNING=true
fi

# Backup da configuração
if [ -d /etc/nginx ]; then
    cp -r /etc/nginx /etc/nginx.backup.$(date +%Y%m%d_%H%M%S) &
fi

# Compilação paralela das dependências
log "Compilando dependências HTTP/3 em paralelo"
cd /tmp
rm -rf sfparse nghttp3 ngtcp2

build_dependency() {
    local repo=$1 dir=$2
    if ! git clone --depth=1 "$repo" "$dir"; then
        echo "Falha no clone de $dir, continuando..."
        return 1
    fi
    cd "$dir" && autoreconf -fi
    ./configure --prefix=/usr/local > /dev/null
    make -j$(get_cores) > /dev/null && make install > /dev/null &
}

build_dependency https://github.com/ngtcp2/sfparse.git  sfparse
build_dependency https://github.com/ngtcp2/nghttp3.git  nghttp3
build_dependency https://github.com/ngtcp2/ngtcp2.git  ngtcp2
wait

# Configuração de variáveis de ambiente
export CFLAGS="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2"
export LDFLAGS="-Wl,--as-needed -Wl,-z,relro -Wl,-z,now"

# Preparação do ambiente
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Estrutura de diretórios
mkdir -p /etc/nginx/{conf.d,sites-available,sites-enabled,geoip2,modules}
mkdir -p /var/log/nginx /var/cache/nginx /var/run /var/lock

# Configuração do usuário
if ! getent group www-data >/dev/null; then groupadd --system www-data; fi
if ! getent passwd www-data >/dev/null; then 
    useradd --system --no-create-home --shell /usr/sbin/nologin -g www-data www-data
fi
chown -R www-data:www-data /var/log/nginx /var/cache/nginx

# Download de fontes
log "Baixando códigos-fonte"
cd "$BUILD_DIR"

download_nginx() {
    if ! wget -q "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"; then
        retry wget -q "https://github.com/nginx/nginx/archive/release-${NGINX_VERSION}.tar.gz"  -O "nginx-${NGINX_VERSION}.tar.gz"
    fi
}

download_nginx &

# Módulos adicionais
retry git clone --depth=1 https://github.com/google/ngx_brotli.git  &
retry git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git  &
retry git clone --depth=1 https://github.com/leev/ngx_http_geoip2_module.git  &

# OpenSSL
if ! git clone --depth=1 -b ${OPENSSL_VERSION} https://github.com/openssl/openssl.git  quic-openssl; then
    OPENSSL_CONFIG=""
else
    OPENSSL_CONFIG="--with-openssl=../quic-openssl --with-openssl-opt=\"enable-tls1_3 enable-ktls enable-quic\""
fi

wait

# Extração do NGINX
tar -xzf nginx-${NGINX_VERSION}.tar.gz

# Compilação do Brotli
if [ -d "ngx_brotli" ]; then
    cd ngx_brotli/deps/brotli
    mkdir -p out && cd out
    cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF > /dev/null
    make brotlienc brotlidec brotlicommon -j$(get_cores) > /dev/null &
    cd "$BUILD_DIR"
fi

# Configuração do NGINX
cd nginx-${NGINX_VERSION}

CONFIGURE_ARGS="--prefix=/etc/nginx \
  --sbin-path=/usr/sbin/nginx \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/var/run/nginx.pid \
  --lock-path=/var/lock/nginx.lock \
  --user=www-data --group=www-data \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_realip_module \
  --with-http_stub_status_module \
  --with-http_gzip_static_module \
  --with-http_sub_module \
  --with-http_mp4_module \
  --with-http_slice_module \
  --with-http_auth_request_module \
  --with-http_dav_module \
  --with-threads --with-file-aio \
  --with-stream --with-stream_ssl_module \
  --with-compat"

# Adicionar HTTP/3 se disponível
if [ -n "$OPENSSL_CONFIG" ]; then
    CONFIGURE_ARGS="$CONFIGURE_ARGS --with-http_v3_module $OPENSSL_CONFIG"
fi

# Adicionar módulos
[ -d "../ngx_brotli" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS --add-module=../ngx_brotli"
[ -d "../headers-more-nginx-module" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS --add-module=../headers-more-nginx-module"
[ -d "../ngx_http_geoip2_module" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS --add-module=../ngx_http_geoip2_module"
[ -d "../njs/nginx" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS --add-dynamic-module=../njs/nginx"

log "Executando configure"
./configure $CONFIGURE_ARGS > /dev/null

log "Compilando NGINX"
make -j$(get_cores) > /dev/null

# Instalação
if [ -f /usr/sbin/nginx ]; then
    cp /usr/sbin/nginx /usr/sbin/nginx.backup.$(date +%Y%m%d_%H%M%S)
fi
make install > /dev/null

# Instalação do NJS
if [ -f "objs/ngx_http_js_module.so" ]; then
    cp objs/ngx_http_js_module.so /etc/nginx/modules/
    if [ -f /etc/nginx/nginx.conf ] && ! grep -q "ngx_http_js_module.so" /etc/nginx/nginx.conf; then
        sed -i '1iload_module modules/ngx_http_js_module.so;' /etc/nginx/nginx.conf
    fi
fi

# Configuração GeoIP2
log "Configurando GeoIP2"
mkdir -p /etc/nginx/geoip2
cd /etc/nginx/geoip2
rm -f GeoIP2-Country.mmdb*

GEOIP_URLS=(
    "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb.gz" 
    "https://dl.miyuru.lk/geoip/maxmind/country/maxmind.dat.gz" 
)

for url in "${GEOIP_URLS[@]}"; do
    if wget -q --timeout=30 --tries=2 "$url" -O GeoIP2-Country.mmdb.gz; then
        gzip -df GeoIP2-Country.mmdb.gz > /dev/null 2>&1 && break
    fi
done

# Verificação de dependências
log "Verificando dependências de runtime"
detect_openssl_pkg() {
    for cand in libssl3 libssl1.1 libssl1.0.0; do
        if apt-cache policy "$cand" | grep -q 'Candidate: [0-9]'; then
            echo "$cand"
            return
        fi
    done
    echo "openssl"
}

OPENSSL_PKG=$(detect_openssl_pkg)
apt-get install -y --no-install-recommends "$OPENSSL_PKG" ${RUNTIME_DEPS[@]:-libpcre3 zlib1g libmaxminddb0} > /dev/null

# Reinício do serviço
if [ "$NGINX_WAS_RUNNING" = true ]; then
    systemctl start nginx
fi

log "Build concluído com sucesso"
echo "Versão: $NGINX_VERSION"
echo "Módulos: SSL, HTTP/2${OPENSSL_CONFIG:+, HTTP/3}, Brotli, Headers More, GeoIP2, NJS"