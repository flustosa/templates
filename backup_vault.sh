#!/bin/bash

FILENAME=vw-data-$(date +%d-%m-%y).tar.gz
LOGFILE=/var/log/vault-backup.log

# Carregando as variáveis SLUG e PING_KEY do healthcheck.io

while IFS= read -r line || [ -n "$line" ]; do
  # Ignorar linhas vazias ou comecando com #
  [[ -z "$line" || "$line" == \#* ]] && continue
  
  # Extração da chave e valor, removendo aspas aoedor do valor, se houver
  key=$(echo "$line" | cut -d '=' -f 1)
  value=$(echo "$line" | cut -d '=' -f 2-)

  # Remover aspas simples ou duplas ao redor do valor
  value=$(echo "$value" | sed -e 's/^["'\'']//;s/["'\'']$//')

  # Exportar a variável
  export "$key=$value"
done < /usr/local/sbin/.env


log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOGFILE
}

health_check () {

        ENDPOINT="https://hc-ping.com"
	URL="$ENDPOINT/$PING_KEY/$SLUG_BACKUP"
	
        case $1 in
                start) curl -fsS -m 10 --retry 3 $ENDPOINT/$PING_KEY/$SLUG_BACKUP/\start > /dev/null ;;
                fail) curl -fsS -m 10 --retry 3 $ENDPOINT/$PING_KEY/$SLUG_BACKUP/fail > /dev/null ;;
                1) curl -fsS -m 10 --retry 3 $ENDPOINT/$PING_KEY/$SLUG_BACKUP/fail > /dev/null ;;
                success) curl -fsS -m 10 --retry 3 $ENDPOINT/$PING_KEY/$SLUG_BACKUP> /dev/null ;;
                0) curl -fsS -m 10 --retry 3 $ENDPOINT/$PING_KEY/$SLUG_BACKUP/success > /dev/null ;;
                logg) curl -fsS -m 10 --retry 3 --data-raw "$m" $ENDPOINT/$PING_KEY/$SLUG_BACKUP/log > /dev/null ;;
        esac

}


run_command() {
    local command="$1"
    local success_message="$2"
    local error_message="$3"

    # Executa o comando
    eval "$command"

    # Verifica o status de saída
    if [ $? -ne 0 ]; then
        log "[ERRO] $error_message"
        exit 1
    else
        if [ -n "$success_message" ]; then
            log "[INFO] $success_message"
        fi
    fi
}

run_backup() {
	
	run_command "cd $VAULT_DIR" "" "Falha ao acessar o diretório $VAULT_DIR" &&
	run_command "docker compose stop" "VaultWarden - Stack Stopped" "Falha ao parar a stack do Docker" &&
	run_command "tar cvzf $VAULT_PATH/$FILENAME $VAULT_DIR/vw-data" "Vaultwarden - Arquivo de backup criado" "Falha ao criar o backup" &&
	run_command "rclone copy $VAULT_PATH/$FILENAME 'gdrive:/ZZ. BACKUPS'" "VaultWarden - Content Backed Upto Google Drive" "Falha ao copiar o backup para o Google Drive" ||  return 1
	
}

run_script() {

	health_check start
	run_backup
	BACKUP_STATUS=$?

	if [ $BACKUP_STATUS -eq 0 ]; then
	    health_check success
	    log "[INFO] Backup concluído com sucesso"
	else
	    log "[ERROR] Erro ao realizar o backup"
	    health_check fail
	fi
	
	run_command "docker compose start" "VaultWarden - Stack Started" "Falha ao iniciar a stack do Docker" 
}

run_script
