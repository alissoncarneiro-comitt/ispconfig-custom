# ISPConfig Custom Installer

Este projeto fornece uma stack completa e modularizada com:

✅ ISPConfig via autoinstaller (branch `stable`)  
✅ NGINX compilado com Brotli, HTTP/3, GeoIP2, headers-more, njs  
✅ PHP 8.2 / 8.3 / 8.4 via sockets (`update-alternatives`)  
✅ Templates otimizados para Laravel/WordPress  
✅ Prometheus + Grafana  
✅ Backups com Rclone + Google Drive  
✅ Arquitetura modular via scripts bash

## Estrutura dos Diretórios

```
├── README.md
├── ispconfig-autoinstaller
│   ├── LICENSE
│   ├── README.md
│   ├── ispc3-ai.sh
│   ├── ispconfig.ai.php
│   └── lib
│   ├── class.ISPConfig.inc.php
│   ├── class.ISPConfigConnector.inc.php
│   ├── class.ISPConfigDatabase.inc.php
│   ├── class.ISPConfigFunctions.inc.php
│   ├── class.ISPConfigHTTP.inc.php
│   ├── class.ISPConfigHTTPResponse.inc.php
│   ├── class.ISPConfigLog.inc.php
│   ├── exceptions
│   │   └── class.ISPConfigException.inc.php
│   ├── libbashcolor.inc.php
│   └── os
│   ├── class.ISPConfigBaseOS.inc.php
│   ├── class.ISPConfigDebian10OS.inc.php
│   ├── class.ISPConfigDebian11OS.inc.php
│   ├── class.ISPConfigDebian12OS.inc.php
│   ├── class.ISPConfigDebianOS.inc.php
│   ├── class.ISPConfigUbuntu2004OS.inc.php
│   ├── class.ISPConfigUbuntu2204OS.inc.php
│   ├── class.ISPConfigUbuntu2404OS.inc.php
│   └── class.ISPConfigUbuntuOS.inc.php
├── scripts
│   ├── install-full.sh
│   ├── install-templates.sh
│   ├── monitoring
│   │   ├── exporters
│   │   │   ├── mysqld_exporter.sh
│   │   │   ├── nginx_exporter.sh
│   │   │   ├── node_exporter.sh
│   │   │   └── php_fpm_exporter.sh
│   │   ├── grafana.sh
│   │   ├── prometheus.sh
│   │   └── setup.sh
│   ├── nginx
│   │   ├── conf.d
│   │   │   └── nginx.conf
│   │   ├── setup.sh
│   │   ├── snippets
│   │   │   ├── fastcgi-cache.conf
│   │   │   ├── fastcgi-php.conf
│   │   │   ├── laravel.conf
│   │   │   ├── security-headers.conf
│   │   │   ├── ssl-params.conf
│   │   │   └── wordpress.conf
│   │   └── templates
│   │   └── nginx_vhost.conf.master
│   └── php
│   ├── Untitled-2.sh
│   ├── pools.d
│   │   └── ispconfig.conf.template
│   └── setup-fpm.sh
└── templates
├── nginx_template
│   └── custom_tpl.php
└── php_fpm_pool
└── custom_pool.conf.master
```

## Instalação

```bash
# Clonar com submódulo
git clone --recursive https://github.com/alissoncarneiro-comitt/ispconfig-custom.git
cd ispconfig-custom

# Compilar NGINX / PHP
sudo ./scripts/nginx/setup.sh
sudo ./scripts/php/setup-fpm.sh

# Instalar ISPConfig + Templates
sudo ./scripts/install-full.sh

# Instalar Monitoring
sudo ./scripts/monitoring/setup.sh

# Instalar fail2ban
sudo ./scripts/fail2ban/setup.sh

```
