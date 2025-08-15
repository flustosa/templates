#!/usr/bin/env bash


setup_healthcheck_io () {
    echo -e "$ACTION - Informe a chave (PING_KEY) para configuração dos alertas no healthcheck.io:"
    PING_KEY="skaESZdhgXMsrXFI7eSIow"                       


    # Use system's hostname as check's slug                                  
    SLUG=$(hostname)                                                         
    
    PARAMS="{'api_key': '$PING_KEY', 'slug': '$SLUG', 'schedule': '0 30 * * *', 'tz': 'America/Sao_Paulo'}" # Construct a ping URL and append "?create=1" at the end:
    URL="https://healthchecks.io/api/v3/checks/"
 
    # Send success signal to Healthchecks.io
    curl -m 10 --retry 5 $URL --data "$PARAMS"
}

setup_healthcheck_io
