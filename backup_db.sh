#!/bin/bash
set -euo pipefail

# -- Parámetro: nombre de la BD
if [ $# -lt 1 ]; then
  echo "Uso: $0 <NOMBRE_BASE_DATOS>"
  exit 1
fi
DB_NAME="$1"

# -- Paths y timestamps
BACKUP_DIR="$HOME/backups/mysql"
LOG_FILE="$HOME/scripts/backup.log"
DATESTAMP=$(date +%F_%H-%M-%S)

mkdir -p "$BACKUP_DIR" "$HOME/scripts"

# -- 1) Inicio de log
echo "[$(date +'%F %T')] → Iniciando backup de $DB_NAME" >> "$LOG_FILE"

# -- 2) Dump y compresión
mysqldump --single-transaction --quick --no-tablespaces \
  --routines --add-drop-table --disable-keys --extended-insert --comments \
  --databases "$DB_NAME" \
  | gzip > "$BACKUP_DIR/${DB_NAME}_$DATESTAMP.sql.gz"

# -- 3) Fin de log
echo "[$(date +'%F %T')] ← Backup completado: $BACKUP_DIR/${DB_NAME}_$DATESTAMP.sql.gz" >> "$LOG_FILE"

# -- 4) Limpieza de >7 días
find "$BACKUP_DIR" -type f -iname "*.sql.gz" -mtime +7 -delete

# -- 5) Cargar configuración del NAS
declare -A nas_conf
read_nas_conf() {
  awk -F= '/^\[nas\]/{flag=1;next}/^\[/{flag=0}flag && NF==2 {
    key=$1; gsub(/ /,"",key)
    val=$2; gsub(/^ +| +$/,"",val)
    print key"="val
  }' ~/.nas.conf
}
while IFS='=' read -r key val; do
  nas_conf["$key"]="$val"
done < <(read_nas_conf)

NAS_SERVER="${nas_conf[server]}"
NAS_SHARE="${nas_conf[share]}"
NAS_USER="${nas_conf[username]}"
NAS_PASS="${nas_conf[password]}"
NAS_DEST="${nas_conf[dest_dir]}"

# -- 6) Subida con smbclient
#    Quita -W si tu dominio no es WORKGROUP
smbclient "//$NAS_SERVER/$NAS_SHARE" \
  -U "$NAS_USER%$NAS_PASS" \
  -m SMB3 \
  -c "lcd $BACKUP_DIR; cd $NAS_DEST; put ${DB_NAME}_$DATESTAMP.sql.gz; exit" \
  >> "$LOG_FILE" 2>&1

echo "[$(date +'%F %T')] Copiado a NAS //$NAS_SERVER/$NAS_SHARE/$NAS_DEST/${DB_NAME}_$DATESTAMP.sql.gz" >> "$LOG_FILE"



