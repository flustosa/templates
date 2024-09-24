#!/usr/bin/env bash

# SCRIPT DE ATUALIZACAO (Testado no Ubuntu 22.04 LTS e 24.04 LTS)
## REQUISITOS PARA USO DO SCRIPT
### Conta no healthcheck.io (ou serviço auto-hospedado)
### Executar script com privilégios de root (sudo ou root)

# Carregando as variáveis SLUG e PING_KEY do healthcheck.io
set -a
source .env
set +a

health_check () {
        ENDPOINT="https://hc-ping.com"

        case $1 in
                start) curl -fsS --retry 3 $ENDPOINT/$PING_KEY/$SLUG/\start > /dev/null ;;
                fail) curl -fsS --retry 3 $ENDPOINT/$PING_KEY/$SLUG/fail > /dev/null ;;
                1) curl -fsS --retry 3 $ENDPOINT/$PING_KEY/$SLUG/fail > /dev/null ;;
                success) curl -fsS --retry 3 $ENDPOINT/$PING_KEY/$SLUG> /dev/null ;;
                0) curl -fsS --retry 3 $ENDPOINT/$PING_KEY/$SLUG/success > /dev/null ;;
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
    if pgrep -x "apt-get" > /dev/null || pgrep -x "dpkg" > /dev/null; then
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

    return 0  # Sucesso
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

