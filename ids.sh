#!/bin/bash

# Fonction pour générer un ID unique pour le conteneur
generate_id() {
    id=$1
    while pct list | awk '{print $1}' | grep -q "^$id$"; do
        ((id++))
    done
    echo $id
}

# Mise à jour des templates disponibles
pveam update
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst

# Variables
template="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
storage="local-lvm"
gateway="10.0.2.15"
bridge="vmbr0"
password="password"

# Déploiement de Suricata
suricata_id=$(generate_id 250)  # Utilisation d'un ID unique
suricata_ip="10.0.2.$suricata_id"
suricata_hostname="suricata"

# Stocker l'ID du conteneur Suricata
echo "$suricata_id" > /tmp/suricata_id

# Créer le conteneur pour Suricata
pct create $suricata_id $template \
    --hostname $suricata_hostname \
    --storage $storage \
    --password $password \
    --rootfs 4 \
    --cpuunits 1024 \
    --memory 1024 \
    --net0 name=eth0,ip=$suricata_ip/24,gw=$gateway,bridge=$bridge

# Démarrer le conteneur Suricata
pct start $suricata_id
sleep 10

# Installer Suricata et ses dépendances
pct exec $suricata_id -- bash -c "apt update && apt install -y suricata jq"

# Configurer Suricata pour écouter sur l'interface réseau
pct exec $suricata_id -- bash -c "sed -i 's/interface: eth0/interface: eth0/' /etc/suricata/suricata.yaml"

# Activer l'écoute sur tout le réseau 10.0.2.0/24
pct exec $suricata_id -- bash -c "sed -i 's/home-net: \[.*\]/home-net: [10.0.2.0\/24]/' /etc/suricata/suricata.yaml"

# Activer Suricata au démarrage et le lancer immédiatement
pct exec $suricata_id -- systemctl enable suricata
pct exec $suricata_id -- systemctl restart suricata

echo "Suricata est déployé avec succès sur $suricata_ip et écoute le réseau 10.0.2.0/24"