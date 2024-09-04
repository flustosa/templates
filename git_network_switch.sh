#!/bin/bash

# Identificar a rede atual
CURRENT_SSID=$(nmcli -t -f active,ssid dev wifi | egrep '^(yes|sim)' | cut -d':' -f2)

# Definir o SSID da rede corporativa
CORPORATE_SSID="CD-COLABORADORES"

if [ "$CURRENT_SSID" == "$CORPORATE_SSID" ]; then
    echo "Conectado à rede corporativa: $CORPORATE_SSID"
    git config --global url."ssh://git@ssh.github.com:443/".insteadOf "git@github.com:"
#    git config --global url."ssh://git@ssh.github.com:443/".insteadOf "ssh://git@github.com/"
    echo "Configuração do Git ajustada para usar a porta 443."

else
    echo "Você não está na rede corporativa. Mantendo as configurações padrão."
    git config --global --unset url.ssh://git@ssh.github.com:443/.insteadOf
    echo "Configuração do Git restaurada para usar a porta 22."

fi

