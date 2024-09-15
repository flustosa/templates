#!/bin/bash

################# AUTO UPDATE  + CRONTAB #######################

create_cron () {
        CRON="30 0 * * * $PWD/backup.sh"
        cp ./tempcron ./tempcron.copy 2>/dev/null
        rm ./tempcron
        (sudo crontab -l 2>/dev/null 1>./tempcron) && (printf "\n" >> ./tempcron && printf "%s" "$CRON" >> ./tempcron && printf "\n" >>./tempcron)
        sudo crontab ./tempcron
        
}

create_autoupdate () {
        curl -o ./autoupdate.sh https://raw.githubusercontent.com/flustosa/templates/master/autoupdate.sh
        chmod +x ./autoupdate.sh
        create_cron     
}

create_autoupdate
