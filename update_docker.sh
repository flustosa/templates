#!/bin/bash

# DEPENDENCIAS
# - msmtp 


# CONFIGURACOES
# - msmtp default config file (/etc/msmtprc) 
# - .env: WEBHOOK_URL, EMAIL_TO, EMAIL_FROM, DOCKER_HUB_PASS (key to pull images above limit without auth)
SCRIPT_DIR="/usr/local/sbin"
set -a
source "$SCRIPT_DIR"/.env
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

    local email_body=$(mktemp)

    # Gerar conteúdo do produto
    local product_logo_or_name
    if [[ -n "$PRODUCT_LOGO" ]]; then
        product_logo_or_name="<img src=\"$PRODUCT_LOGO\" class=\"email-logo\" alt=\"Logo\"/>"
    else
        product_logo_or_name="$PRODUCT_NAME"
    fi

# Usar printf para substituir placeholders
    {
        printf '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">\n'
        printf '<html xmlns="http://www.w3.org/1999/xhtml">\n'
        printf '<head><meta name="viewport" content="width=device-width, initial-scale=1.0" />\n'
        printf '<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />\n'
        printf '<style type="text/css">%s</style>\n' "$(cat template_styles.css)"  # Se houver CSS externo
        printf '</head>\n<body dir="ltr">\n'
        printf '<table class="email-wrapper" width="100%%" cellpadding="0" cellspacing="0">\n'
        printf '<tr><td class="content"><table class="email-content" width="100%%" cellpadding="0" cellspacing="0">\n'
        printf '<tr><td class="email-masthead"><a class="email-masthead_name" href="%s" target="_blank">%s</a></td></tr>\n' "$PRODUCT_LINK" "$product_logo_or_name"
        printf '<tr><td class="email-body" width="100%%"><table class="email-body_inner" align="center" width="570" cellpadding="0" cellspacing="0">\n'
        printf '<tr><td class="content-cell">%s</td></tr>\n' "$body"
        printf '</table></td></tr>\n'
        printf '<tr><td><table class="email-footer" align="center" width="570" cellpadding="0" cellspacing="0">\n'
        printf '<tr><td class="content-cell"><p class="sub center">%s</p></td></tr>\n' "$COPYRIGHT"
        printf '</table></td></tr>\n</table></td></tr>\n</table>\n</body>\n</html>'
    } > "$email_body"

    # Enviar email 
    (
        echo "From: $EMAIL_FROM"
        echo "To: $EMAIL_TO"
        echo "Subject: $subject"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=UTF-8"
        echo
        cat "$email_body"
    ) | msmtp -a default -t "$EMAIL_TO"

}

    # Debug: Exibir conteúdo temporário (opcional)
    echo "=== Conteúdo do Email (Debug) ==="
    #cat "$email_body"
    echo "================================"

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
	    compose_results+="<ul>"
		for entry in "${compose_updates[@]}"; do
		    compose_results+="<li>$entry</li>"
		done
	    compose_results+="</ul>"
	fi

    	if [[ ${#compose_errors[@]} -gt 0 ]]; then
             compose_results+="<h3>Erros ao Atualizar Composes:</h3><ul>"
        	for entry in "${compose_errors[@]}"; do
	            compose_results+="<li>$entry</li>"
	        done
             compose_results+="</ul>"
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

    # Adiciona imagens removidas com sucesso
    if [[ ${#prune_results[@]} -gt 0 ]]; then
        prune_messages+="<h3>Imagens Removidas:</h3><ul>"
        for entry in "${prune_results[@]}"; do
            prune_messages+="<li>$entry</li>"
        done
        prune_messages+="</ul>"
    fi

    # Adiciona erros
    if [[ ${#prune_errors[@]} -gt 0 ]]; then
        prune_messages+="<h3>Erros ao Remover Imagens:</h3><ul>"
        for entry in "${prune_errors[@]}"; do
            prune_messages+="<li>$entry</li>"
        done
        prune_messages+="</ul>"
    fi

    echo "$prune_messages"
}


check_for_updates() {
    echo "Buscando imagens Docker dos containers em execução..."
    local running_containers=$(docker ps --format "{{.Names}}|{{.Image}}|{{.Status}}" | tr -s ' ' | tr -d '\r')

    local body="<h1>Relatório de Atualizações Docker</h1>"

    # Tabela de containers e status de atualização
    body+="<h2>Containers e Status de Atualização</h2>"
    body+="<table border='1' cellpadding='5' cellspacing='0' style='border-collapse: collapse;'>"
    body+="<tr><th>Container Name</th><th>Image</th><th>Status</th><th>Resultado da Atualização</th></tr>"

    while IFS='|' read -r container_name image container_status; do
        image_name=$(echo "$image" | cut -d ':' -f 1)
        current_tag=$(echo "$image" | cut -d ':' -f 2)

        # Verifica se a tag é fixa (não é latest, release ou stable)
        if [[ "$current_tag" != "latest" && "$current_tag" != "release" && "$current_tag" != "stable" ]]; then
            body+="<tr><td>$container_name</td><td>$image</td><td>$container_status</td><td>Versão fixa ($current_tag)</td></tr>"
            continue
        fi

        # Tenta atualizar a imagem
        pull_output=$(docker pull "$image" 2>&1)
        pull_status=$?

        if [[ $pull_status -eq 0 ]]; then
            if [[ "$pull_output" == *"Image is up to date"* ]]; then
                body+="<tr><td>$container_name</td><td>$image</td><td>$container_status</td><td>Já estava atualizada</td></tr>"
            else
                body+="<tr><td>$container_name</td><td>$image</td><td>$container_status</td><td>Atualizada com sucesso</td></tr>"
            fi
        else
            body+="<tr><td>$container_name</td><td>$image</td><td>$container_status</td><td>Erro: ${pull_output//$'\n'/ }</td></tr>"
        fi
    done <<< "$running_containers"

    body+="</table>"

    # Composes e Prune (converta saídas para HTML)
    local compose_results=$(update_compose)
    body+="<h2>Composes atualizados:</h2>"
    if [[ -n "$compose_results" ]]; then
        body+="$compose_results"
    else
        body+="<p>Nenhum docker compose para subir.</p>"
    fi

    # Lista de imagens
        body+="<h2>Lista de Imagens</h2>"
	    body+="<table border='1' cellpadding='5' cellspacing='0' style='border-collapse: collapse;'>"
	        body+="<tr><th>REPOSITORY</th><th>TAG</th><th>IMAGE ID</th><th>CREATED</th></tr>"

		    local docker_images=$(docker images --format "{{.Repository}}|{{.Tag}}|{{.ID}}|{{.CreatedSince}}" | tr -s ' ' | tr -d '\r')
		        while IFS='|' read -r repository tag image_id created; do
				        if [[ "$repository" != "<none>" ]]; then # Ignora imagens sem repositório/tag
						            body+="<tr><td>$repository</td><td>$tag</td><td>$image_id</td><td>$created</td></tr>"
							            fi
								        done <<< "$docker_images"

									    body+="</table>"


    local prune_results=$(prune_images)
    body+="<h2>Limpeza de Imagens</h2>"
    if [[ -n "$prune_results" ]]; then
        body+="$prune_results"
    else
        body+="<p>Nenhuma imagem disponível para exclusão.</p>"
    fi

    send_email "$body"
}

check_for_updates
