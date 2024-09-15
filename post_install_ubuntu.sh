#!/usr/bin/env bash

# post_install_ubuntu.sh - Initial setup and installation of programs for Ubuntu 
#
# Website:       https://homelab.app.br
# Author:        Felipe Lustosa
# Maintenance:   Felipe Lustosa
#
# ------------------------------------------------------------------------ #
# WHAT IT DOES?
# This script installs and configures selected applications on a fresh Ubuntu installation.
# 
#
# CONFIGURATION?
# 
# HOW TO USE IT?
# Examples:
# $ ./init_ubuntu.sh
# You have to change the variables to chose what to install on Ubuntu
# ------------------------------------------------------------------------ #
# Changelog:
#
#   v1.0 18/06/2023, Felipe Lustosa:
#     - First version with comments!
#   v1.1 04/08/2024, Felipe Lustosa:
#     - Added more programs
#   v1.2 14/08/2024, Felipe Lustosa:
#     - Added git config function
#
# ------------------------------------------------------------------------ #
# Tested on:
#   bash 5.1.16
# ------------------------------------------------------------------------ #

# -------------------------------VARIABLES----------------------------------------- #
# You may change
#
# -------------------------------FUTURE IMPLEMENTATIONS----------------------------------------- #
# - config wakeonlan
# - SSH Setup: Change default port (22) for a higher one / Disable root access via SSH
# - update .bashrc and create folders () + .tmux.conf
# - .bashrc guide https://www.freecodecamp.org/news/vimrc-configuration-guide-customize-your-vim-editor/
# - config files for tmux
# - Create autoupdate script -> include log | after -> centralized logging
# - curl autoupdate.sh file and update crontab to execute daily
# - Configure Python environment: pip, venv
# - Add SSH key configuration for Github access (also check "push" alias in .vimrc) 

### VARIABLES ###
INFO="\e[1;36m[INFO]\e[0m" 		# Cyan + bold
ERROR="\e[1;91m[ERROR]\e[0m" 		# light red + bold
ACTION="\e[1;92m[ACTION]\e[0m" 		# light green + bold
DOWNLOAD_FOLDER_PROGRAMS="$HOME/Downloads/programs"
REQUIREMENTS=(
	sudo
	wget
	curl
)

APT_PROGRAMS_TO_INSTALL=(
	git
	openssh-server
	openssh-client
	htop
	ethtool
	make
	wakeonlan	
	xtail
	#snapd
	#tmux
	bat # visual for cat -> batcat
 	neovim
  	tldr
)

DEB_PROGRAMS_TO_INSTALL=(
	http://archive.ubuntu.com/ubuntu/pool/universe/c/cmatrix/cmatrix_2.0-3_amd64.deb
)

SNAP_PROGRAMS_TO_INSTALL=(
	#postman
)


SNAP_PROGRAMS=()


confirm () {
        read confirm && [[ $confirm == [yYsS] ]]
}

### FUNCTION NOT YET IMPLEMENTED
check_apt_programs () {
RESPONSE='y'
for program in ${APT_PROGRAMS_TO_INSTALL[@]}; do
	echo -e "$ACTION - Install $program? [Y/n]"
 	read RESPONSE
  	if [[ ! ${RESPONSE,,} = "y" ]]; then
  		echo -e "$INFO - Following to the next program..."
   	else
    	SNAP_PROGRAMS+=($program)
	 	echo $SNAP_PROGRAMS
   	fi
echo $SNAP_PROGRAMS
done
}

### REQUIREMENTS TEST ###
connection_test () {
	echo -e "$INFO - Testing connection..."
	if ! sudo ping -c 1 8.8.8.8 -q &> /dev/null; then
		echo -e "$ERROR - No internet connection, check the network status."
		exit 1
	else
		echo -e "$INFO - Internet connection working properly."
	fi
}
check_basic_programs () {
	echo -e "$INFO - Checking basic programs..."
	for program in ${REQUIREMENTS[@]}; do
		if [[ ! -x $(which $program) ]]; then
			echo -e "$INFO - $program not installed."
			echo -e "$INFO - Installing $program."
			sudo apt install $program -y
		else
			echo -e "$INFO - $program already installed."
		fi
	done
}
requirementes_test () {
	echo -e "$INFO - Testing requirements..."
	connection_test
	check_basic_programs
	
}

### FUNCTIONS ###

add_i386_architecture () {
	echo -e "$INFO - Adding i386 architecture..."
	sudo dpkg --add-architecture i386
} 
update_repositories  () {
	echo -e "$INFO - Updating repositories..."
	sudo apt update
}
download_deb_packages () {
	[[ ! -d "$DOWNLOAD_FOLDER_PROGRAMS"  ]] && mkdir -p "$DOWNLOAD_FOLDER_PROGRAMS" # -p creates parent directories if needded
	for url in ${DEB_PROGRAMS_TO_INSTALL[@]}; do
		url_extraida=$(echo ${url##*/} | sed 's/-/_/g' | cut -d _ -f 1)
		if ! dpkg -l | grep -iq $url_extraida; then
			echo -e "$INFO - Baixando o arquivo $url_extraida..."
			wget -c "$url" -P "$DOWNLOAD_FOLDER_PROGRAMS"
			echo -e "$INFO - Instalando o $url_extraida..."
			sudo dpkg -i $DOWNLOAD_FOLDER_PROGRAMS/${url##*/}
			echo -e "$INFO - Instalando depenências..."
			sudo apt -f install -y
		else
			echo -e "$INFO - The program $url_extraida is already installed."
		fi
	done
}
install_apt_packages () {
	for program in ${APT_PROGRAMS_TO_INSTALL[@]}; do
	  if ! dpkg -l | grep -q $program; then
  	    echo -e "$INFO - Instalando o $program..."
	    sudo apt install $program -y
	  else
	    echo -e "$INFO - O pacote $program ja esta instalado."
	  fi
	done
	}
install_snap_packages () {  	## para instalacao de aplicativos via snap, verificar instalacao do requisito##
	if [[ ! -x $(which snapd) ]]; then
		echo -e "$INFO - Snap nao esta instalado."
		echo -e "$INFO - Instalando Snap."
		sudo apt install snapd -y
	else
		echo -e "$INFO - Snap ja esta instalado."
	fi
	for program in ${SNAP_PROGRAMS_TO_INSTALL[@]}; do
	  if ! snap list | grep -q $program; then
	    sudo snap install $program
	  else
	    echo -e "$INFO - O pacote $program ja esta instalado."
	  fi
	done
	}	

################## DOCKER INSTALLATION ##################

docker_install () {
	curl -fsSL https://get.docker.com -o get-docker.sh
	sh get-docker.sh
}

################## ADD SUDO USER ##################

add_sudo_user () {
RESPONSE="y"
	while [[ ${RESPONSE,,} = "y" ]]; do
		echo -e "$INFO - Criando usuario..."
		echo -e "$INFO - O nome deve comecar com uma letra minuscula, o restante dos caracteres podem ser letras minusculas, numeros, '-' ou '_' "
		echo -e "$ACTION - Informe o nome do usuario: "
		read NEW_USER
		if [[ ! $(sudo cat /etc/passwd | grep -wi $NEW_USER) ]] ; then
			echo -e "$INFO - Criando o usuario ${NEW_USER,,}..."
			sudo adduser --gecos '' ${NEW_USER,,}
			echo -e "$INFO - Incluindo usuario ${NEW_USER,,} no grupo \e[1;4msudo\e[0m..."
			sudo usermod -aG sudo $NEW_USER
		else
			echo -e "$ERROR - Usuario ${NEW_USER,,} ja existe no sistema!"
		fi
		echo -e "$ACTION - Deseja criar outro usuario? [Y/n]"
		read RESPONSE
			if [[ ! ${RESPONSE,,} = "y" ]]; then
			echo -e "$INFO - Seguindo para as proximas etapas de instalacao..."	
			fi
	done			
} 

################## SETUP GIT USER ##################

setup_git () {

	### CHECK GIT INSTALLATION ###
 	if [[ ! $(which git) ]]; then
		echo -e "$ERROR - Git not found! Do you want to install and continue? [Y/n]"
		if confirm; then
			sudo apt install git
		else
			return 1
		fi
	fi
 
 	### SETUP GIT ###
 	echo -e "$INFO - Vamos configurar o git..."
	echo -e "$ACTION - Informe o nome de usuario do SISTEMA para configurar o Git: "
	read NEW_USER
	USER=true
	while [[ ! $(sudo cat /etc/passwd | grep -wi $NEW_USER) ]]
	do
			echo -e "$ERROR - Informe um nome de usuário válido, que exista no sistema!"
			read NEW_USER
	done
			echo -e "$ACTION - Informe o nome de usuario git: "
			read GIT_USER
			echo -e "$ACTION - Informe o e-mail de usuario git: "
			read GIT_EMAIL
			sudo -H -u $NEW_USER bash -c "git config --global user.name ${GIT_USER}"
			sudo -H -u $NEW_USER bash -c "git config --global user.email ${GIT_EMAIL}"
			USER=false
}


################## CONFIGURAR VIM #################

setup_vim () {

	### CHECK VIM INSTALL ###
 	if [[ ! $(which nvim) ]]; then
		echo -e "$ERROR - Neovim não encontrado! Deseja instalar e continuar? [Y/n]"
		if confirm; then
			sudo apt install neovim
		else
			return 1
		fi
	fi
 
 	### SETUP VIM ###
 	echo -e "$INFO - Vamos configurar o vim..."
	echo -e "$ACTION - Informe o nome de usuario do SISTEMA para configurar o Vim: "
	read NEW_USER
	USER=true
	while [[ ! $(sudo cat /etc/passwd | grep -wi $NEW_USER) ]]
	do
			echo -e "$ERROR - Informe um nome de usuário válido, que exista no sistema!"
			read NEW_USER
	done
			echo -e "$INFO - Criando a estrutura de diretórios..."
			sudo -H -u $NEW_USER bash -c "mkdir -p ~/.vim ~/.vim/autoload ~/.vim/backup ~/.vim/colors ~/.vim/plugged"
			sudo -H -u $NEW_USER bash -c "curl -o ~/.vimrc https://raw.githubusercontent.com/flustosa/templates/master/.vimrc"
			echo -e "$INFO - Após a instalação reabrir o terminal ou abrir o VIM e realizar o comando ":source" para atualizar as configurações!" 

			USER=false
}


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



################## ATUALIZACAO FINAL ##################

last_update () {
    echo -e "$INFO - Fazendo o upgrade e limpeza do sistema..."
	sudo apt update -y && sudo apt upgrade -y
	sudo apt autoclean
	sudo apt autoremove -y
}


################# CONFIRMA INSTALAÇÕES ######################

echo -e "$INFO - Iniciando a instalacao e configuracao dos programas essenciais no Ubuntu 22.04."
declare -A options
options[update_repositories ]='Atualizar repositórios? [Y/N]: '
options[requirementes_test]='Testar requisitos [Y/N]?: '
options[add_sudo_user]='Adicionar usuário SUDO? [Y/N]: '
options[setup_git]='Configurar usuário git? [Y/N]: '
options[setup_vim]='Configurar o VIM? [Y/N]: '
options[add_i386_architecture]='Adicionar arquitetura i386? [Y/N]: '
options[download_deb_packages]='Baixar pacotes deb? [Y/N]: '
options[install_apt_packages]='Instalar pacotes apt? [Y/N]: '
options[install_snap_packages]='Instalar pacotes snap? [Y/N]: '
options[docker_install]='Insalar docker e docker-compose? [Y/N]: '
options[create_autoupdate]='Criar configurações de autoupdate no crontab? [Y/N]: '
options[last_update]='Realizar limpeza dos pactoes não utilizados? [Y/N]: '

################## FUNCOES PARA EXECUCAO ##################

check_functions () {
        echo -e "Confirme a configuração em cada etapa:"
        for option in ${!options[@]}; do
                printf "${options[$option]}"
                if confirm ; then
                        $option
                fi  
	done
}

check_functions

