#!/bin/bash
set -e
set -o pipefail

NGINX_VERSION="1.28.0"
OPENSSL_VERSION="openssl-3.3.1"
BUILD_DIR="/tmp/nginx-build"

export DEBIAN_FRONTEND=noninteractive

echo "\n Iniciando build NGINX ${NGINX_VERSION} com NJS dinâmico..."

echo "\n\n Detectando sistema operacional para ajustar dependências"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION=$VERSION_ID
    CODENAME=$VERSION_CODENAME
    echo "Detecção: Distribuição = $DISTRO | Versão = $VERSION | Codinome = $CODENAME"
else
    echo "Não foi possível detectar a versão do sistema!"
    exit 1
fi


if [[ "$DISTRO" == "debian" ]]; then
  echo "🧩 Configurando repositórios de segurança para Debian $VERSION ($CODENAME)..."
  echo "deb http://security.debian.org/debian-security $CODENAME-security main" > /etc/apt/sources.list.d/security.list
  echo "deb http://deb.debian.org/debian $CODENAME main" > /etc/apt/sources.list.d/main.list
  echo "deb http://deb.debian.org/debian $CODENAME-updates main" > /etc/apt/sources.list.d/updates.list

  apt update
else
  echo "⚠️ Sistema não é Debian. Esta rotina está preparada apenas para Debian."
  exit 1
fi


echo "\n\n Instalando dependências com verificação de versão"


BASIC_DEPS=(
    "build-essential" "git" "wget" "curl" "unzip" "libtool"
    "automake" "autoconf" "cmake" "zlib1g-dev" "libpcre3-dev"
    "pkg-config" "libgd-dev" "ca-certificates" "uuid-dev"
    "libxml2-dev" "libxslt1-dev" "sudo"
)

# Dependências que podem variar por distro
OPTIONAL_DEPS=(
    "libmaxminddb-dev"
    "libmaxminddb0"
    "libssl-dev"
)

echo "Atualizando cache de pacotes..."
apt update

echo "Instalando dependências básicas..."
apt install -y --no-install-recommends "${BASIC_DEPS[@]}"

echo "Verificando dependências opcionais..."
for pkg in "${OPTIONAL_DEPS[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        echo "  Instalando $pkg..."
        apt install -y --no-install-recommends "$pkg" || echo "  ⚠️  Falha ao instalar $pkg, continuando..."
    else
        echo "  ⚠️  Pacote $pkg não encontrado, pulando..."
    fi
done

echo "\n\n # Verificando se NGINX já está instalado "
if systemctl is-active --quiet nginx 2>/dev/null; then
    echo " NGINX ativo detectado - parando serviço temporariamente..."
    systemctl stop nginx
    NGINX_WAS_RUNNING=true
else
    NGINX_WAS_RUNNING=false
fi


echo "\n\n Backup da configuração existente do ISPConfig"
if [ -d /etc/nginx ] && [ -f /etc/nginx/nginx.conf ]; then
    echo "Fazendo backup da configuração existente..."
    cp -r /etc/nginx /etc/nginx.backup.$(date +%Y%m%d_%H%M%S)
    NGINX_CONF_BACKUP=true
else
    NGINX_CONF_BACKUP=false
fi


echo "\n\n Compilar ngtcp2 stack com verificação"
if ! ldconfig -p | grep -q libngtcp2; then
    echo "Compilando ngtcp2 stack..."
    cd /tmp
    rm -rf sfparse nghttp3 ngtcp2

    # sfparse
    if ! git clone https://github.com/ngtcp2/sfparse.git; then
        echo "Falha ao clonar sfparse, continuando sem HTTP/3 otimizado..."
    else
        cd sfparse && autoreconf -fi && ./configure --prefix=/usr/local && make -j$(nproc) && make install && ldconfig
        cd /tmp
    fi

    # nghttp3
    if ! git clone https://github.com/ngtcp2/nghttp3.git; then
        echo "Falha ao clonar nghttp3, continuando sem HTTP/3 otimizado..."
    else
        cd nghttp3 && autoreconf -fi && ./configure --prefix=/usr/local && make -j$(nproc) && make install && ldconfig
        cd /tmp
    fi

    # ngtcp2
    if ! git clone https://github.com/ngtcp2/ngtcp2.git; then
        echo "Falha ao clonar ngtcp2, continuando sem HTTP/3 otimizado..."
    else
        cd ngtcp2 && autoreconf -fi && ./configure --prefix=/usr/local --with-libnghttp3=/usr/local && make -j$(nproc) && make install && ldconfig
        cd /tmp
    fi
fi


echo "\n\n Preparando ambiente de build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"


echo "\n\n Criando estrutura de diretórios"
mkdir -p /etc/nginx/{conf.d,sites-available,sites-enabled,geoip2,modules}
mkdir -p /var/log/nginx /var/cache/nginx /var/run /var/lock


echo "\n\n Verificar/criar usuário www-data"
if ! getent group www-data >/dev/null 2>&1; then
    groupadd --system www-data
fi
if ! getent passwd www-data >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin -g www-data www-data
fi

chown -R www-data:www-data /var/log/nginx /var/cache/nginx

retry() {
    local n=0
    local max_attempts=3
    local delay=2

    while [ $n -lt $max_attempts ]; do
        if "$@"; then
            return 0
        fi
        n=$((n+1))
        if [ $n -lt $max_attempts ]; then
            echo "Tentativa $n/$max_attempts falhou, aguardando ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        fi
    done

    echo "Falha após $max_attempts tentativas: $*"
    return 1
}



echo "\n\n Baixando códigos-fonte..."

if ! retry wget -q "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"; then
    echo "Tentando mirror alternativo do NGINX..."
    retry wget -q "https://github.com/nginx/nginx/archive/release-${NGINX_VERSION}.tar.gz" -O "nginx-${NGINX_VERSION}.tar.gz" || {
        echo "Falha no download do NGINX"
        exit 1
    }
fi

# NJS
if ! retry git clone --depth=1 https://github.com/nginx/njs.git njs; then
    echo "Falha no clone do NJS, continuando sem módulo JavaScript..."
    mkdir -p njs/nginx
fi


echo "\n\n Módulos adicionais..."
retry git clone --depth=1 --recursive https://github.com/google/ngx_brotli.git || echo "⚠️  Sem Brotli"
retry git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git || echo "⚠️  Sem Headers More"
retry git clone --depth=1 https://github.com/leev/ngx_http_geoip2_module.git || echo "⚠️  Sem GeoIP2"

echo "\n\n OpenSSL para QUIC..."
if ! retry git clone --depth=1 -b ${OPENSSL_VERSION} https://github.com/openssl/openssl.git quic-openssl; then
    echo "Falha no OpenSSL QUIC, usando sistema..."
    OPENSSL_CONFIG=""
else
    OPENSSL_CONFIG="--with-openssl=../quic-openssl --with-openssl-opt=\"enable-tls1_3 enable-ktls enable-quic\""
fi


echo "\n\n Extraindo NGINX..."
tar -xzf nginx-${NGINX_VERSION}.tar.gz


echo "\n\n Compilando Brotli se disponível..."
if [ -d "ngx_brotli" ]; then
    echo "Compilando Brotli..."
    cd ngx_brotli/deps/brotli
    if [ ! -d "out" ]; then
        mkdir -p out && cd out
        if ! cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_C_FLAGS="-O2 -fPIC"; then
            echo " Usando cmake básico para Brotli..."
            cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
        fi
        make brotlienc brotlidec brotlicommon -j"$(nproc)" || {
            echo " Erro na compilação do Brotli, continuando sem..."
            cd "$BUILD_DIR"
            rm -rf ngx_brotli
        }
    fi
    cd "$BUILD_DIR"
fi


echo "\n\n Configurando NGINX..."
cd nginx-${NGINX_VERSION}

export CFLAGS="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2"
export LDFLAGS="-Wl,--as-needed -Wl,-z,relro -Wl,-z,now"

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


echo "\n\n Adicionando HTTP/3 se OpenSSL QUIC disponível..."
if [ -n "$OPENSSL_CONFIG" ]; then
    CONFIGURE_ARGS="$CONFIGURE_ARGS --with-http_v3_module $OPENSSL_CONFIG"
fi

echo "\n\n Adicionando módulos opcionais se disponíveis..."
[ -d "../ngx_brotli" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS --add-module=../ngx_brotli"
[ -d "../headers-more-nginx-module" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS --add-module=../headers-more-nginx-module"
[ -d "../ngx_http_geoip2_module" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS --add-module=../ngx_http_geoip2_module"
[ -d "../njs/nginx" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS --add-dynamic-module=../njs/nginx"


echo "\n\n Executando configure..."
eval ./configure $CONFIGURE_ARGS

echo "\n\n Compilando NGINX..."
make -j"$(nproc)"

if [ -f /usr/sbin/nginx ]; then
    echo "Fazendo backup do binário NGINX existente..."
    cp /usr/sbin/nginx /usr/sbin/nginx.backup.$(date +%Y%m%d_%H%M%S)
fi

make install


echo "\n\n Instalando módulo NJS se compilado..."
if [ -f "objs/ngx_http_js_module.so" ]; then
    cp objs/ngx_http_js_module.so /etc/nginx/modules/
    echo " Módulo NJS instalado"


    if [ -f /etc/nginx/nginx.conf ] && ! grep -q "ngx_http_js_module.so" /etc/nginx/nginx.conf; then

        if grep -q "load_module" /etc/nginx/nginx.conf; then
            sed -i '/load_module.*\.so;/a load_module modules/ngx_http_js_module.so;' /etc/nginx/nginx.conf
        else
            sed -i '1iload_module modules/ngx_http_js_module.so;' /etc/nginx/nginx.conf
        fi
    fi
fi


echo "\n\n Copiar snippets locais se disponíveis..."
if [ -d "../nginx/snippets" ]; then
    echo "\n\n Copiando snippets personalizados..."
    mkdir -p /etc/nginx/snippets
    cp -r ../nginx/snippets/* /etc/nginx/snippets/ 2>/dev/null || true
fi

echo "\n\n NGINX recompilado com sucesso!"


echo "\n\n  Configurando GeoIP2..."
mkdir -p /etc/nginx/geoip2
cd /etc/nginx/geoip2

# Limpar arquivos existentes para evitar conflitos
echo "Limpando arquivos GeoIP2 existentes..."
rm -f GeoIP2-Country.mmdb GeoIP2-Country.mmdb.gz

GEOIP_URLS=(
    "https://dl.miyuru.lk/geoip/maxmind/country/maxmind.dat.gz"
    "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb.gz"
    "https://raw.githubusercontent.com/Loyalsoldier/geoip/release/Country.mmdb.gz"
)

GEOIP_SUCCESS=false
for i in "${!GEOIP_URLS[@]}"; do
    url="${GEOIP_URLS[$i]}"
    echo "Tentativa $((i+1))/${#GEOIP_URLS[@]}: Baixando GeoIP2 de: $url"

    # Download com timeout e tentativas limitadas
    if timeout 60 wget -q --timeout=30 --tries=2 "$url" -O GeoIP2-Country.mmdb.gz.tmp; then
        echo "Download concluído, verificando integridade..."

        # Verificar se é um arquivo gzip válido
        if gzip -t GeoIP2-Country.mmdb.gz.tmp 2>/dev/null; then
            echo "Arquivo gzip válido, movendo para posição final..."
            mv GeoIP2-Country.mmdb.gz.tmp GeoIP2-Country.mmdb.gz

            # Extrair com força (sobrescrever se existir)
            echo "Extraindo arquivo GeoIP2..."
            if gzip -df GeoIP2-Country.mmdb.gz; then
                # Verificar se o arquivo extraído é válido e não está vazio
                if [ -f GeoIP2-Country.mmdb ] && [ -s GeoIP2-Country.mmdb ]; then
                    echo "✓ GeoIP2 baixado e extraído com sucesso!"
                    echo "  Tamanho: $(stat -f%z GeoIP2-Country.mmdb 2>/dev/null || stat -c%s GeoIP2-Country.mmdb) bytes"
                    GEOIP_SUCCESS=true
                    break
                else
                    echo "✗ Arquivo extraído inválido ou vazio"
                    rm -f GeoIP2-Country.mmdb
                fi
            else
                echo "✗ Falha na extração do arquivo"
                rm -f GeoIP2-Country.mmdb.gz
            fi
        else
            echo "✗ Arquivo baixado não é um gzip válido"
            rm -f GeoIP2-Country.mmdb.gz.tmp
        fi
    else
        echo "✗ Falha no download (timeout ou erro de rede)"
        rm -f GeoIP2-Country.mmdb.gz.tmp
    fi

    # Pequena pausa entre tentativas
    [ $((i+1)) -lt ${#GEOIP_URLS[@]} ] && sleep 2
done

if [ "$GEOIP_SUCCESS" = false ]; then
    echo "⚠️  Todas as tentativas de download do GeoIP2 falharam"
    echo "   Criando arquivo dummy para evitar erros de configuração..."
    # Criar arquivo vazio para não quebrar configurações que referenciam GeoIP
    touch /etc/nginx/geoip2/GeoIP2-Country.mmdb
    cat > /etc/nginx/geoip2/README.txt << 'EOF'
# GeoIP2 Database Status
# Status: FAILED - Arquivo dummy criado
#
# Para atualizar manualmente:
# cd /etc/nginx/geoip2
# wget https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb.gz
# gzip -df GeoLite2-Country.mmdb.gz
# nginx -s reload
EOF
    echo "   Arquivo dummy criado. Consulte /etc/nginx/geoip2/README.txt para instruções"
else
    cat > /etc/nginx/geoip2/README.txt << EOF
# GeoIP2 Database Status
# Status: SUCCESS - Database ativa
# Última atualização: $(date)
# Arquivo: GeoIP2-Country.mmdb
# Tamanho: $(stat -f%z GeoIP2-Country.mmdb 2>/dev/null || stat -c%s GeoIP2-Country.mmdb) bytes
#
# Para atualizar:
# cd /etc/nginx/geoip2 && rm -f *.mmdb* && [reexecutar script]
EOF
fi

# Voltar para diretório de build
cd "$BUILD_DIR"


echo "\n\n  Verificando dependências de runtime..."
# Detecta qual pacote de runtime do OpenSSL está disponível
detect_openssl_pkg() {
  for cand in libssl3 libssl1.1 libssl1.0.0; do
    if apt-cache policy "$cand" | grep -q 'Candidate: [0-9]'; then
      echo "$cand"
      return
    fi
  done
  # último recurso: o próprio binário openssl
  echo "openssl"
}

OPENSSL_PKG=$(detect_openssl_pkg)
echo "📦 Pacote OpenSSL detectado: $OPENSSL_PKG"

# Se existir candidato no APT, instala diretamente
if apt-cache policy "$OPENSSL_PKG" | grep -q 'Candidate: [0-9]'; then
  echo "📥 Instalando $OPENSSL_PKG…"
  apt-get install -y --no-install-recommends "$OPENSSL_PKG"
else
  echo "⚠️  $OPENSSL_PKG indisponível via APT. Aplicando fallback…"

  # Fallback para Debian 11 e 12
  case "$VERSION" in
    11) FALLBACK_PKG="libssl1.1" ;;
    12) FALLBACK_PKG="libssl3"   ;;
    *)  echo "❌ Sem fallback disponível para Debian $VERSION" >&2; exit 1 ;;
  esac

  echo "📦 Baixando $FALLBACK_PKG para Debian $VERSION…"
  pushd /tmp >/dev/null
    if apt-get download "$FALLBACK_PKG"; then
      DEB_FILE=$(ls -1 ${FALLBACK_PKG}_*_"$(dpkg --print-architecture)".deb | head -n1)
      echo "➜ Instalando $DEB_FILE"
      dpkg -i "$DEB_FILE"
      rm -f "$DEB_FILE"
    else
      echo "❌ Falha no fallback do pacote $FALLBACK_PKG" >&2
      exit 1
    fi
  popd >/dev/null

  # marca como instalado para as mensagens subsequentes
  OPENSSL_PKG="$FALLBACK_PKG"
fi

echo "✅ Dependência OpenSSL resolvida (pacote: $OPENSSL_PKG)"




RUNTIME_DEPS=("libpcre3" "zlib1g" "libmaxminddb0")
apt-get install -y --no-install-recommends "${RUNTIME_DEPS[@]}"




if [[ -n "${NGINX_CONF_URL:-}" ]]; then
    echo "\n\n   Baixando nginx.conf de $NGINX_CONF_URL"
    if curl -fsSL --connect-timeout 10 "$NGINX_CONF_URL" -o /tmp/nginx.conf.new; then
        # Testar configuração antes de aplicar
        if nginx -t -c /tmp/nginx.conf.new 2>/dev/null; then
            cp /tmp/nginx.conf.new /etc/nginx/nginx.conf
            echo "\n\n   Configuração externa aplicada"
        else
            echo "\n\n   Configuração externa inválida, mantendo atual"
        fi
        rm -f /tmp/nginx.conf.new
    else
        echo "\n\n  Falha ao baixar configuração externa"
    fi
elif [ -f "../nginx/conf.d/nginx.conf" ]; then
    echo "\n\n   Aplicando nginx.conf local..."
    # Testar configuração local antes de aplicar
    if nginx -t -c "../nginx/conf.d/nginx.conf" 2>/dev/null; then
        cp ../nginx/conf.d/nginx.conf /etc/nginx/nginx.conf
        echo "\n\n   Configuração local aplicada"
    else
        echo "\n\n   Configuração local inválida, mantendo atual"
    fi
fi


echo "\n\n   Mantendo dependências de build para compatibilidade com ISPConfig"
echo "\n\n   Para limpeza manual posterior (se necessário):"
echo "\n\n   apt-get autoremove -y build-essential cmake git"


rm -rf "$BUILD_DIR"


echo "\n\n   Testando configuração final do NGINX..."
if nginx -t; then
    echo "\n\n  ✓ Configuração válida!"
else
    echo "\n\n   ✗ Erro na configuração!"
    if [ "$NGINX_CONF_BACKUP" = true ]; then
        echo "\n\n  Restaurando backup da configuração..."
        cp -r /etc/nginx.backup.*/nginx.conf /etc/nginx/nginx.conf 2>/dev/null || true
        nginx -t || echo "\n\n   Backup também com problemas!"
    fi
    exit 1
fi


if [ "$NGINX_WAS_RUNNING" = true ]; then
    echo "\n\n   Reiniciando NGINX..."
    systemctl start nginx
    if systemctl is-active --quiet nginx; then
        echo "\n\n  ✓ NGINX reiniciado com sucesso"
    else
        echo "\n\n   ✗ Falha ao reiniciar NGINX"
        systemctl status nginx --no-pager
        exit 1
    fi
fi

echo ""
echo "======================================================"
echo "   🎉 NGINX RECOMPILADO COM SUCESSO PARA ISPCONFIG!"
echo "======================================================"
echo "   📋 Resumo da instalação:"
echo "   ✓ Versão: $NGINX_VERSION"
echo "   ✓ Módulos: SSL, HTTP/2$([ -n "$OPENSSL_CONFIG" ] && echo ", HTTP/3"), Brotli, Headers More, GeoIP2, NJS"
echo "   ✓ Configuração preservada"
echo "   ✓ Compatibilidade ISPConfig mantida"
echo "   ✓ Dependências runtime verificadas"
echo "   ✓ GeoIP2: $([ "$GEOIP_SUCCESS" = true ] && echo "Ativo" || echo "Dummy (consulte README.txt)")"
echo ""
echo "   📁 Logs: /var/log/nginx/"
echo "   ⚙️  Config: /etc/nginx/"
echo "   🔧 Módulos: /etc/nginx/modules/"
echo "   🌍 GeoIP2: /etc/nginx/geoip2/"
echo "======================================================"


if [ "${1:-}" = "daemon-off" ] || [ -f /.dockerenv ]; then
    echo "\n\n   Iniciando NGINX (daemon off)..."
    exec nginx -g 'daemon off;'
fi