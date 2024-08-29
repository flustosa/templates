#!/usr/bin/env bash
timestamp () {
	date +%d/%m/%y"-"%X" (GMT"%Z")"
} 
auto_update () {
	timestamp && echo -e "[INFO] - Iniciando atualizacao..."
	/usr/bin/apt apt update && /usr/bin/apt apt -y upgrade
	timestamp && echo -e "[INFO] - Fim da atualizacao."
} 
auto_update >> /var/log/apt/myupdates.log
