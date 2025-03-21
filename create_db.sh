#!/bin/bash

# Générer un ID unique pour le conteneur
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
read -sp "Entrez le mot de passe pour la VM base de données (sécurisé de préférence lol): " password

db_id=$(generate_id 101)
db_ip="10.0.2.$db_id"
db_hostname="db-$db_id"

# Créer le conteneur de base de données (MySQL par exemple)
pct create $db_id $template \
    --hostname $db_hostname \
    --storage $storage \
    --password $password \
    --rootfs 2 \
    --cpuunits 1 \
    --memory 512 \
    --net0 name=eth0,ip=$db_ip/24,gw=$gateway,bridge=$bridge

# Démarrer le conteneur de base de données
pct start $db_id
sleep 10

# Synchroniser l'horloge pour éviter les erreurs d'update
pct exec $db_id -- bash -c "timedatectl set-ntp on"

# Installer MySQL avec une attente pour éviter les erreurs de mise à jour
pct exec $db_id -- bash -c "sleep 30 && apt update && apt install -y mysql-server"

# Vérifier que MySQL est bien installé
pct exec $db_id -- bash -c "mysql --version"

# Sécuriser MySQL
pct exec $db_id -- bash -c "mysql_secure_installation"

# Créer une base de données pour l'application
pct exec $db_id -- bash -c "mysql -e \"CREATE DATABASE db_$db_id;\""

# Configurer MySQL pour autoriser uniquement les connexions depuis 10.0.2.0/24
pct exec $db_id -- bash -c "sed -i 's/bind-address\s*=\s*127.0.0.1/bind-address = 10.0.2.$db_id/' /etc/mysql/mysql.conf.d/mysqld.cnf"

# Appliquer des règles iptables pour restreindre l'accès
pct exec $db_id -- bash -c "iptables -A INPUT -p tcp --dport 3306 -s 10.0.2.0/24 -j ACCEPT"
pct exec $db_id -- bash -c "iptables -A INPUT -p tcp --dport 3306 -j DROP"

# Redémarrer MySQL pour appliquer les changements
pct exec $db_id -- bash -c "systemctl restart mysql"

# Afficher l'adresse IP de la base de données
echo "Base de données déployée avec succès sur $db_ip avec restriction d'accès à 10.0.2.0/24"