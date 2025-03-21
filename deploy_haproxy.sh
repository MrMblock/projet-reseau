#!/bin/bash

# Générer un ID unique pour HAProxy
generate_id() {
    id=$1
    while pct list | awk '{print $1}' | grep -q "^$id$"; do
        ((id++))
    done
    echo $id
}

pveam update
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst

# Variables
template="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
storage="local-lvm"
gateway="10.0.2.15"
bridge="vmbr0"
read -sp "Entrez le mot de passe pour la VM HAProxy: " password

# Déploiement de HAProxy
haproxy_id=$(generate_id 100)
haproxy_ip="10.0.2.$haproxy_id"
haproxy_hostname="haproxy-$haproxy_id"

# Créer le conteneur HAProxy
pct create $haproxy_id $template \
    --hostname $haproxy_hostname \
    --storage $storage \
    --password $password \
    --rootfs 2 \
    --cpuunits 1 \
    --memory 512 \
    --net0 name=eth0,ip=$haproxy_ip/24,gw=$gateway,bridge=$bridge

# Démarrer le conteneur HAProxy
pct start $haproxy_id
sleep 10

# Installer HAProxy et ModSecurity
pct exec $haproxy_id -- bash -c "
apt update && apt install -y haproxy libmodsecurity3 libmodsecurity-dev nginx-mod-http-modsecurity git
"

# Cloner et configurer OWASP ModSecurity CRS
pct exec $haproxy_id -- bash -c "
git clone --depth 1 https://github.com/coreruleset/coreruleset.git /etc/haproxy/modsecurity-crs
cp /etc/haproxy/modsecurity-crs/crs-setup.conf.example /etc/haproxy/modsecurity-crs/crs-setup.conf
"

# Générer un certificat auto-signé
pct exec $haproxy_id -- bash -c "
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/haproxy.key \
    -out /etc/ssl/certs/haproxy.crt \
    -subj '/C=FR/ST=Paris/L=Paris/O=IT/CN=haproxy'
cat /etc/ssl/certs/haproxy.crt /etc/ssl/private/haproxy.key > /etc/ssl/certs/haproxy.pem
"

# Configurer HAProxy avec ModSecurity
pct exec $haproxy_id -- bash -c "echo '
global
    log stdout format raw local0
    maxconn 4096
    lua-load /usr/share/haproxy-modsecurity/modsecurity.lua

defaults
    log global
    timeout client 30s
    timeout connect 5s
    timeout server 30s

frontend https_front
    bind *:443 ssl crt /etc/ssl/certs/haproxy.pem
    mode http
    http-request lua.modsecurity
    default_backend web_servers

frontend http_front
    bind *:80
    mode http
    http-request redirect scheme https code 301 if !{ ssl_fc }

backend web_servers
    balance roundrobin
' > /etc/haproxy/haproxy.cfg"

# Redémarrer HAProxy
pct exec $haproxy_id -- systemctl restart haproxy

echo "HAProxy avec ModSecurity est déployé avec succès sur $haproxy_ip"
