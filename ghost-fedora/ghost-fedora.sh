#!/usr/bin/env bash
#
# This script is used to install the Ghost blog on Fedora and assumes a CLEAN
# machine will DESTROY nginx config. The ghost service runs as the 'ghost' user
# and is rooted at /var/www/ghost.
#
# Run this script then configure ghost and nginx for your specific domain.
#
# Useful system management:
# - Ghost is installed and run as user 'ghost' when npm is executed
# - Restart the ghost service: systemctl restart ghost
# - Restart nginx: systemctl restart nginx
# - Ghost configuration dir: /var/www/ghost-*/
# - Nginx ghost config: /etc/nginx/conf.d/*.conf
#
# IMPORTANT NOTE:
# Be sure there is sufficient RAM and swap space! The ghost install will fail
# on systems with 512MB and no swap space. Using `--verbose` might get around
# the issue but it's just luck. Follow this:
# https://www.digitalocean.com/community/tutorials/how-to-add-swap-on-centos-7
#

set -ex

dnf install -y python gcc gcc-c++ make automake
dnf install -y nginx nodejs npm unzip

GHOST_URL=blog.ljdelight.com
GHOST_ROOT=/var/www/ghost-${GHOST_URL}
GHOST_PORT=2368
GHOST_USER=ghost
GHOST_GROUP=${GHOST_USER}
GHOST_VERSION=0.11.3

useradd --system --create-home --shell /bin/false --user-group ${GHOST_USER}

mkdir -p ${GHOST_ROOT}

pushd ${GHOST_ROOT}
  curl -L https://github.com/TryGhost/Ghost/releases/download/${GHOST_VERSION}/Ghost-${GHOST_VERSION}.zip -o ../ghost.zip
  unzip ../ghost.zip -d .
popd

cat > ${GHOST_ROOT}/config.js << EOL
var path = require('path'),
    config;

config = {
    // ### Production
    // When running Ghost in the wild, use the production environment.
    // Configure your URL and mail settings here
    production: {
        url: 'http://${GHOST_URL}',
        mail: {},
        database: {
            client: 'sqlite3',
            connection: {
                filename: path.join(__dirname, '/content/data/ghost.db')
            },
            debug: false
        },

        server: {
            host: '127.0.0.1',
            port: '${GHOST_PORT}'
        }
    }
};
module.exports = config;
EOL

chown -R ${GHOST_USER}:${GHOST_GROUP} ${GHOST_ROOT}
sudo -H -u ghost /bin/bash -c "cd ${GHOST_ROOT} && npm install --production"

cat > /etc/systemd/system/ghost-${GHOST_URL}.service << EOL
[Unit]
Description=ghost
After=network.target

[Service]
Type=simple
WorkingDirectory=${GHOST_ROOT}
User=${GHOST_USER}
Group=${GHOST_GROUP}
Environment=NODE_ENV=production
ExecStart=/usr/bin/node index.js
Restart=on-failure
SyslogIdentifier=ghost-${GHOST_URL}

[Install]
WantedBy=multi-user.target
EOL


cat > /etc/nginx/conf.d/${GHOST_URL}.conf << EOL
server {
    listen 80 default_server;
    # listen [::]:80 default_server ipv6only=on;
    # listen 443 default_server ssl;
    # listen [::]:443 default_server ipv6only=on ssl;

    server_name ${GHOST_URL};
    client_max_body_size 2G;

    # ssl_certificate /etc/nginx/ssl/${GHOST_URL}.crt;
    # ssl_certificate_key /etc/nginx/ssl/${GHOST_URL}.pem;

    location / {
        proxy_pass http://localhost:${GHOST_PORT};
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
    }
}
EOL


cat > /etc/nginx/nginx.conf << EOL
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;
    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;
    include /etc/nginx/conf.d/*.conf;
    gzip on;
    gzip_disable "msie6";
    # ssl_protocols TLSv1.1 TLSv1.2;
    # ssl_ciphers "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!3DES:!MD5:!PSK";
    # ssl_dhparam /etc/ssl/certs/dhparam.pem;
    # ssl_prefer_server_ciphers on;
    # ssl_session_cache shared:SSL:10m;
}
EOL


systemctl daemon-reload
systemctl restart ghost-${GHOST_URL}.service nginx
systemctl enable ghost-${GHOST_URL}.service nginx

echo "Disable selinux!"
echo "Configure ghost at ${GHOST_ROOT}"
