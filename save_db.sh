#!/bin/bash

# Dossier de sauvegarde
BACKUP_DIR="/var/backups/mysql"
DATE=$(date +%F)
RETENTION_DAYS=7

# Créer le dossier de sauvegarde s'il n'existe pas
mkdir -p $BACKUP_DIR

# Liste des conteneurs LXC
containers=$(pct list | awk 'NR>1 {print $1}')

for ct in $containers; do
    echo "Vérification du conteneur $ct..."

    # Vérifier si MySQL est installé dans le conteneur
    if pct exec $ct -- bash -c "command -v mysql" &> /dev/null; then
        echo "MySQL détecté sur le conteneur $ct, lancement de la sauvegarde..."

        # Récupérer les bases de données
        databases=$(pct exec $ct -- bash -c "mysql -u root -e 'SHOW DATABASES;'" | grep -Ev "(Database|information_schema|performance_schema|sys)")

        for db in $databases; do
            echo "Sauvegarde de la base de données: $db dans le conteneur $ct"

            # Effectuer la sauvegarde avec compression
            pct exec $ct -- bash -c "mysqldump -u root --databases $db" | gzip > "$BACKUP_DIR/${ct}_${db}_$DATE.sql.gz"
        done
    else
        echo "MySQL non détecté sur le conteneur $ct, passage au suivant."
    fi
done

# Supprimer les anciennes sauvegardes (plus de X jours)
find $BACKUP_DIR -type f -name "*.sql.gz" -mtime +$RETENTION_DAYS -exec rm {} \;

echo "Sauvegarde de toutes les bases de données terminée."