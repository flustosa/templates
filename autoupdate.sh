#!/usr/bin/env bash

# autoupdate.sh - Autoupdate/upgrade daily Ubuntu 
#
# Website:       https://homelab.app.br
# Author:        Felipe Lustosa
# Maintenance:   Felipe Lustosa
#
# ------------------------------------------------------------------------ #
# WHAT IT DOES?
# This script run apt-update and apt-upgrade daily using crontab and restart the system if needed. 
# 
# CONFIGURATION?
# It's configured by ./init_ubuntu.sh
#
# ------------------------------------------------------------------------ #
# Changelog:
#
#   v0.1 18/06/2024, Felipe Lustosa:
#     - First version with comments!
#   v1.0 01/11/2024, Felipe Lustosa:
#     - Added reboot function
#
# ------------------------------------------------------------------------ #
# Tested on:
#   Ubuntu 22.04 and 24.04 LTS
#   bash 5.1.16
# ------------------------------------------------------------------------ #
#


# Carregando as variáveis SLUG e PING_KEY do healthcheck.io

while IFS= read -r line || [ -n "$line" ]; do
  # Ignorar linhas vazias ou começando com #
  [[ -z "$line" || "$line" == \#* ]] && continue
  
  # Extração da chave e valor, removendo aspas ao redor do valor, se houver
  key=$(echo "$line" | cut -d '=' -f 1)
  value=$(echo "$line" | cut -d '=' -f 2-)

  # Remover aspas simples ou duplas ao redor do valor
  value=$(echo "$value" | sed -e 's/^["'\'']//;s/["'\'']$//')

  # Exportar a variável
  export "$key=$value"
done < /usr/local/sbin/.env


health_check () {

        ENDPOINT="https://hc-ping.com"

        case $1 in
                start) curl -fsS -m 10 --retry 3 $ENDPOINT/$PING_KEY/$SLUG/\start > /dev/null ;;
                fail) curl -fsS -m 10 --retry 3 $ENDPOINT/$PING_KEY/$SLUG/fail > /dev/null ;;
                1) curl -fsS -m 10 --retry 3 $ENDPOINT/$PING_KEY/$SLUG/fail > /dev/null ;;
                success) curl -fsS -m 10 --retry 3 $ENDPOINT/$PING_KEY/$SLUG> /dev/null ;;
                0) curl -fsS -m 10 --retry 3 $ENDPOINT/$PING_KEY/$SLUG/success > /dev/null ;;
                logg) curl -fsS -m 10 --retry 3 --data-raw "$m" $ENDPOINT/$PING_KEY/$SLUG/log > /dev/null ;;
        esac

}


auto_update () {     

    LOGFILE="/var/log/apt-update.log"

    log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
    }

    # Verifica se há algum lock em uso
    
    sudo lsof /var/lib/dpkg/lock-frontend > /dev/null 2>&1
    LOCK_STATUS=$?

    sudo lsof /var/cache/apt/archives/lock > /dev/null 2>&1
    LOCK_STATUS2=$?

    # Verifica se o apt ou dpkg está em execução
    if pgrep -x "apt" > /dev/null || pgrep -x "dpkg" > /dev/null; then
        log "Outro processo do apt está em execução. Abortando."
        return 1  # Falha
    fi

    # Definindo variáveis de ambiente
    export NEEDRESTART_MODE=a &&
    export DEBIAN_FRONTEND=noninteractive &&
    export APT_LISTCHANGES_FRONTEND=none &&

    log "Iniciando apt-get update."
    sudo apt-get -qy update >> "$LOGFILE" 2>&1 || return 1  # Se falhar, retorna 1
    log "Concluído apt-get update."

    log "Iniciando apt-get dist-upgrade."
    sudo apt-get -qy dist-upgrade >> "$LOGFILE" 2>&1 || return 1  # Se falhar, retorna 1
    log "Concluído apt-get dist-upgrade."

    log "Iniciando apt-get autoremove."
    sudo apt-get -qy autoremove >> "$LOGFILE" 2>&1 || return 1  # Se falhar, retorna 1
    log "Concluído apt-get autoremove."

    log "Iniciando apt-get clean."
    sudo apt-get clean >> "$LOGFILE" 2>&1 || return 1  # Se falhar, retorna 1
    log "Concluído apt-get clean."

	if [ -f /var/run/reboot-required ]; then
		m="Reboot required. Rebooting system... After reboot, will try to ping healthcheck..."
		touch /usr/local/sbin/rebooted-via-update-script # Arquivo de controle da inicializacao
		health_check logg $m
		shutdown -r now
	else 
    	return 0  # Sucesso
	fi

}


cron_update () {
    health_check start  # Inicia o health check
    auto_update  # Executa o processo de atualização
    UPDATE_STATUS=$?  # Captura o status de retorno do auto_update

    if [ $UPDATE_STATUS -eq 0 ]; then
        health_check success  # Envia notificação de sucesso
   	else
        health_check fail  # Envia notificação de falha
    fi

}

cron_update  # Executa o cron job

