#!/bin/bash

# DEPENDENCIAS
# - msmtp 


# CONFIGURACOES
# - msmtp default config file (/etc/msmtprc) 
# - .env: WEBHOOK_URL, EMAIL_TO, EMAIL_FROM, DOCKER_HUB_PASS (key to pull images above limit without auth)

set -a
source .env
set +a

# Função para enviar notificação via webhook
send_webhook() {
    local message=$1
    curl -X POST -H "Content-Type: application/json" -d "{\"text\": \"$message\"}" "$WEBHOOK_URL"
}

# Função para enviar notificação via email

send_email() {
    server_name=$(uname -n)
    local subject="Docker update: $server_name"
    local body=$1
    echo -e "Subject: $subject\nContent-Type: text/plain; charset=UTF-8\n\n$body" | msmtp -a default -f "$EMAIL_FROM" -t "$EMAIL_TO"
}


update_compose(){
	local compose_files=$(docker compose ls | awk '{print $3}' | sed 1d)
	local compose_updates=()
	local compose_errors=()

	for compose in $compose_files; do
		local output=$(docker compose -f "$compose" up -d --force-recreate 2>&1)
		local status=$?

		if [[ $status -eq 0 ]]; then
		    compose_updates+=("Compose $compose atualizado com sucesso")
		else
		    compose_errors+=("Erro ao atualizar compose $compose: $output")
		fi
	done

	local compose_results=""

    	if [[ ${#compose_updates[@]} -gt 0 ]]; then
        	compose_results+="Composes Atualizados:\n$(IFS=$'\n'; echo "${compose_updates[*]}")\n\n"
	fi

	if [[ ${#compose_errors[@]} -gt 0 ]]; then
		compose_results+="Erros ao Atualizar Composes:\n$(IFS=$'\n'; echo "${compose_errors[*]}")\n\n"
	fi
	echo "$compose_results"
}

## PRUNE IMAGES
prune_images() {
	local docker_images_prune=$(docker images -f dangling=true -q)
	local prune_results=()
	local prune_errors=()

	for image_prune in $docker_images_prune; do
		local output=$(docker rmi $image_prune 2>&1)
		local status=$?

	        if [[ $status -eq 0 ]]; then
		    prune_results+=("Imagem $image_prune removida com sucesso")
		 
	    	else
		    prune_errors+=("Erro ao remover imagem $image_prune: $output")
		fi
	done                                          
	
	local prune_messages=""
    	if [[ ${#prune_results[@]} -gt 0 ]]; then
       		prune_messages+="Imagens Removidas:\n$(IFS=$'\n'; echo "${prune_results[*]}")\n\n"
    	fi
    	if [[ ${#prune_errors[@]} -gt 0 ]]; then
        	prune_messages+="Erros ao Remover Imagens:\n$(IFS=$'\n'; echo "${prune_errors[*]}")\n\n"
    	fi
    	echo "$prune_messages"
	     
}


check_for_updates() {

	echo "Buscando imagens Docker no servidor..."
	docker_images=$(docker images --format "{{.Repository}}:{{.Tag}}")

	local docker_list=$(docker ps --format "Image Name: {{.Names}}\nStatus:{{.Status}}\nImage:{{.Image}}\n")
	local updated_images=()
	local error_images=()
	local ignored_images=()

	for image in $docker_images; do
	    image_name=$(echo $image | cut -d ':' -f 1)
	    current_tag=$(echo $image | cut -d ':' -f 2)
	    echo "Verificando atualizações para a imagem $image_name ($current_tag)..."
	    if [[ "$current_tag" = "latest" || "$current_tag" = "release" || "$current_tag" = "stable" ]]; then
		pull_output=$(docker pull $image 2>&1)
		if [[ $? -eq 0 ]]; then
			if [[ "$pull_output" == *"Image is up to date"* ]]; then
				updated_images+=("Imagem $image_name:$current_tag já estava atualizada\n")
			else
				updated_images+=("Imagem $image_name:$current_tag atualizada com sucesso\n")
			fi
		else
			error_images+=("Erro ao atualizar a imagem $image_name:$current_tag: $pull_output\n")
		fi
	    else
		    ignored_images+=("Ignorando a imagem $image_name:$current_tag pois tem versao fixa\n")
	    fi
	done

	local body=""

	    if [[ ${#docker_list[@]} -gt 0 ]]; then
		body+="\nContainers encontrados:\n$(IFS=$'\n'; echo "${docker_list[*]}")\n\n"
	    else
		body+="\nContainers encontrados:\nNão foram encontrados containers ativos no servidor.\n\n"
	    fi

	    if [[ ${#updated_images[@]} -gt 0 ]]; then
		body+="\nImagens Atualizadas:\n$(IFS=$'\n'; echo "${updated_images[*]}")\n\n"
	    else
		body+="\nImagens Atualizadas:\nNão foram encontradas imagens para atualização.\n\n"
	    fi

	    if [[ ${#error_images[@]} -gt 0 ]]; then
		body+="\nErros ao Atualizar Imagens:\n$(IFS=$'\n'; echo "${error_images[*]}")\n\n"
	    else
		body+="\nErros ao Atualizar Imagens:\nNão houve erros ao atualizar as Imagens.\n\n"
	    fi

	    if [[ ${#ignored_images[@]} -gt 0 ]]; then
		body+="\nImagens Ignoradas:\n$(IFS=$'\n'; echo "${ignored_images[*]}")\n"
	    else
		body+="\nImagens Ignoradas:\nNenhuma imagem foi ignorada.\n\n"
	    fi

	body+="$(update_compose)"
	body+="$(prune_images)"

	send_email "$body"

}

check_for_updates
