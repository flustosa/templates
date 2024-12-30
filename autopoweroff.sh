#!/bin/bash

# Verifica se o usuário possui privilégios de root
if [[ $EUID -ne 0 ]]; then
   echo "Este script deve ser executado como root."
   exit 1
fi

# Função para verificar se há VMs ou contêineres em execução
function verificar_estado() {
  num_vms=$(qm list | grep running | wc -l)
  num_containers=$(lxc-ls -1 --running | wc -l)

  if [ $num_vms -gt 0 ] || [ $num_containers -gt 0 ]; then
    echo "$(date +"%T"): Há VMs ou contêineres em execução. Aguardando..."
    return 0
  else
	echo "No VMs"
  fi
  return 1
}

# Parar todas as VMs
qm_list=$(qm list | grep running | awk '{print $1}')
for i in ${qm_list[@]}; do
        qm stop "${i}"
done

# Parar todos os contêineres
lxc_list=$(lxc-ls -1 --running)
for i in ${lxc_list[@]}; do
        lxc-stop "${i}"
done

# Adicionar um delay inicial para garantir que tudo tenha parado
sleep 30

# Verificar o estado e aguardar por até 3 vezes com intervalos de 30 segundos
for i in {1..3}; do
  if ! verificar_estado; then
    break
  fi
  echo "$(date +"%T"): Aguardando mais 30 segundos..."
  sleep 30
done

# Verificar o estado final
if verificar_estado; then
  echo "Ainda há VMs ou contêineres em execução. Abortando o desligamento."
  exit 1
fi

# Desligar o servidor (substitua "/sbin/shutdown -h now" pelo comando adequado para o seu sistema)
echo "$(date +"%T"): Desligando o servidor..."
/sbin/shutdown -P now
