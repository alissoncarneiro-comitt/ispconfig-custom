<?php
/*
    Template Laravel / WordPress otimizado
*/
?>
server {
    listen 80;
    listen 443 ssl http2;
    server_name {SERVERNAME};
    root {DOCROOT};

    index index.php index.html;

    access_log /var/log/ispconfig/http/{DOMAIN}.access.log;
    error_log  /var/log/ispconfig/http/{DOMAIN}.error.log;

    include snippets/ssl-default.conf;
    include snippets/headers-common.conf;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/lib/php/{PHP_SOCKET};
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
