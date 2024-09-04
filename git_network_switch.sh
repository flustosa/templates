#!/bin/bash


REQUIREMENTS=(
	network-manager
	ping
	git
)

confirm () {
        read confirm && [[ $confirm == [yYsS] ]]
}

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

is_wsl() {
	case "$(uname -r)" in
	*microsoft* ) true ;; # WSL 2
	*Microsoft* ) true ;; # WSL 1
	* ) false;;
	esac
}


# Identificar a rede atual

git_config () {

	if is_wsl; then

		echo "WSL DETECTED: It is not possible to check the network SSID, do you want to chance git configuration to HTTP anyway?"
		if confirm; then
		    git config --global url."ssh://git@ssh.github.com:443/".insteadOf "git@github.com:"
		#    git config --global url."ssh://git@ssh.github.com:443/".insteadOf "ssh://git@github.com/"
		    echo "Configuração do Git ajustada para usar a porta 443."
		fi

	else

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
	fi
}


requirementes_test && git_config
