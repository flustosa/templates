################# AUTO UPDATE  + CRONTAB #######################
CRON_PATH="/usr/local/sbin"

confirm () {
        read confirm && [[ $confirm == [yYsS] ]]
}


create_cron () {
    CRON="30 0 * * * $CRON_PATH/autoupdate.sh"
    cp $CRON_PATH/tempcron $CRON_PATH/tempcron.copy 2>/dev/null
    rm $CRON_PATH/tempcron
    (sudo crontab -l 2>/dev/null 1>$CRON_PATH/tempcron) && (printf "\n" >> $CRON_PATH/tempcron && printf "%s" "$CRON" >> $CRON_PATH/tempcron && printf "\n" >>$CRON_PATH/tempcron)
    sudo crontab $CRON_PATH/tempcron
}

setup_healthcheck_io () {
    echo -e "$ACTION - Informe a chave (PING_KEY) para configuração dos alertas no healthcheck.io:"
    read PING_KEY
    
    printf "PING_KEY=$PING_KEY" > $CRON_PATH/.env
    printf "\n" >> $CRON_PATH/.env
    # Use system's hostname as check's slug
    SLUG=$(hostname)
    printf "SLUG=$SLUG" >> $CRON_PATH/.env
    
    # Construct a ping URL and append "?create=1" at the end:
    URL=https://hc-ping.com/$PING_KEY/$SLUG?create=1

    # Send success signal to Healthchecks.io
    curl -m 10 --retry 5 $URL
}

create_check_reboot () {

	SCRIPT="#!/usr/bin/env bash

LOGFILE=\"/var/log/apt-update.log\"

log() {
    echo \"\$(date '+%Y-%m-%d %H:%M:%S') - \$1\" >> \"\$LOGFILE\"
}   

if [ -f $CRON_PATH/rebooted-via-update-script ]; then
    log \"Reboot realizado com sucesso. Removendo o arquivo de controle...\"
    rm $CRON_PATH/rebooted-via-update-script
    bash $CRON_PATH/autoupdate.sh
fi

"

    echo "$SCRIPT" > $CRON_PATH/check-rebooted.sh
    chmod +x $CRON_PATH/check-rebooted.sh

}

create_reboot_service () {

    SCRIPT="[Unit]
Description=Verificar se o reboot foi realizado pelo script de atualização

[Service]
ExecStart=$CRON_PATH/check-rebooted.sh
Type=oneshot

[Install]
WantedBy=multi-user.target
    "

    echo "$SCRIPT" > /etc/systemd/system/check-rebooted.service
	systemctl enable check-rebooted.service

}


create_autoupdate () {
    curl -o $CRON_PATH/autoupdate.sh https://raw.githubusercontent.com/flustosa/templates/master/autoupdate.sh
    chmod +x $CRON_PATH/autoupdate.sh
    create_cron
    create_check_reboot
	create_reboot_service
    echo -e "$ACTION - Deseja criar um alerta no healthcheck.io? [Y/n]"
    if confirm; then
        setup_healthcheck_io

    fi

}

create_autoupdate
