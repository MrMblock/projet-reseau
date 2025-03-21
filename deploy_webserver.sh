#!/bin/bash

# IP unique à chaque machine
generate_id() {
    id=$1
    while pct list | awk '{print $1}' | grep -q "^$id$"; do
        ((id++))
    done
    echo $id
}

# Variables générales
template="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
storage="local-lvm"
gateway="10.0.2.15"
bridge="vmbr0"
read -sp "Entrez le mot de passe pour le serveur web: " password
echo ""  # Pour ajouter une ligne vide après la saisie du mot de passe

# Demander à l'utilisateur de spécifier l'ID de l'HAProxy avant le déploiement
echo "Veuillez entrer l'id de l'HAProxy sur lequel vous voulez affilier le serveur"
sleep 2
echo "La liste des machines va s'afficher"
echo "-----------------------------------"
pct list
echo "-----------------------------------"
read -p "Rentrez l'ID de l'HAProxy: " haproxy_id
sleep 5

# Demander à l'utilisateur de modifier la configuration de HAProxy
echo "Merci de rajouter le serveur au fichier de configuration HAProxy tel que :"
sleep 6

webserver_id=$(generate_id 200)
echo "server web1 10.0.2.$webserver_id:80 check"
sleep 2
echo "Remplacez le web1 par web suivi le nombre du serveurs actuels, si c'est le deuxieme serveur ajouté, web2"
echo "Le fichier de configuration va s'ouvrir"

sleep 20
pct exec $haproxy_id -- nano /etc/haproxy/haproxy.cfg
pct exec $haproxy_id -- systemctl restart haproxy

webserver_ip="10.0.2.$webserver_id"
webserver_hostname="webserver-$webserver_id"

# Création du conteneur LXC pour le serveur web
pct create $webserver_id $template \
    --hostname $webserver_hostname \
    --storage $storage \
    --password $password \
    --rootfs 2 \
    --cpuunits 1 \
    --memory 512 \
    --net0 name=eth0,ip=$webserver_ip/24,gw=$gateway,bridge=$bridge

# Démarrer le conteneur serveur web
pct start $webserver_id
sleep 10

# Installer Nginx
pct exec $webserver_id -- bash -c "apt install -y nginx"

# Modifier la page index.html pour afficher l'ID du serveur
pct exec $webserver_id -- bash -c "echo '<!DOCTYPE html><html><head><title>Serveur $webserver_id</title></head><body><h1>Serveur ID: $webserver_id</h1></body></html>' > /var/www/html/index.html"

# Redémarrer nginx
pct exec $webserver_id -- systemctl restart nginx

echo "Serveur Web déployé sur l'IP $webserver_ip et ajouté à HAProxy à l'ID $haproxy_id"