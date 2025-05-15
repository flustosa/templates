import os
import time
import RPi.GPIO as GPIO
import logging
import json

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(SCRIPT_DIR, 'config.json')
LOG_FILE = os.path.join(SCRIPT_DIR, 'monitor.log')

# Variáveis de configuração que serão preenchidas ao carregar o config.json
FAN_PIN = None
TEMPERATURA_LIGAR_FAN = None
TIMER = None

fan_ligado = False
sensor_id = ''

logger = logging.getLogger(__name__)

def setup_logging(log_level_str="INFO"):
    """
    Configura o sistema de logging.
    Os logs serão salvos em um arquivo e, opcionalmente, exibidos no console.
    """
    numeric_level = getattr(logging, log_level_str.upper(), None)
    if not isinstance(numeric_level, int):
        logging.basicConfig(level=logging.INFO)
        logger.warning(f"Nível de log inválido '{log_level_str}' no config.json. Usando INFO como padrão.")
        numeric_level = logging.INFO
    else:
        logging.basicConfig(level=numeric_level)

    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    
    file_handler = logging.FileHandler(LOG_FILE)
    file_handler.setFormatter(formatter)
    
    # Configura o handler para exibir logs no console (útil para debug direto)
    # stream_handler = logging.StreamHandler()
    # stream_handler.setFormatter(formatter)
    
    # Limpa handlers existentes para evitar duplicação se setup_logging for chamado múltiplas vezes
    if logger.hasHandlers():
        logger.handlers.clear()
        
    # Adiciona os handlers configurados ao logger
    logger.addHandler(file_handler)
    # logger.addHandler(stream_handler) # Descomente para logar também no console

    # Define o nível de log para ESTE logger específico
    logger.setLevel(numeric_level)
    
    # Impede que os logs sejam propagados para o logger root, evitando mensagens duplicadas no console
    # se o logger root também tiver handlers de console.
    logger.propagate = False 
    logger.info(f"Logging configurado. Nível: {log_level_str.upper()}. Arquivo: {LOG_FILE}")


# --- Funções de Configuração e Sensor ---
def carregar_configuracoes():
    """
    Carrega as configurações do arquivo config.json.
    Retorna True se sucesso, False se falha.
    """
    global FAN_PIN, TEMPERATURA_LIGAR_FAN, TIMER
    
    try:
        with open(CONFIG_FILE, 'r') as f:
            config = json.load(f)
        
        FAN_PIN = config.get('fan_pin')
        TEMPERATURA_LIGAR_FAN = config.get('temperatura_ligar_fan')
        TIMER = config.get('timer')
        log_level_config = config.get('log_level', "INFO") # Padrão para INFO

        # Verifica se as configurações essenciais foram carregadas
        if FAN_PIN is None or TEMPERATURA_LIGAR_FAN is None or TIMER is None:
            # Configura o logging com nível padrão antes de logar o erro, caso ainda não tenha sido configurado
            if not logger.hasHandlers(): setup_logging()
            logger.error("FAN_PIN, TEMPERATURA_LIGAR_FAN ou TIMER não encontrados no arquivo de configuração.")
            return False
        
        # Configura o logging com o nível especificado no arquivo de configuração
        setup_logging(log_level_config)
        
        logger.info("Configurações carregadas com sucesso do arquivo config.json.")
        logger.info(f"  Pino do Ventilador (FAN_PIN): {FAN_PIN}")
        logger.info(f"  Temperatura para Ligar Ventilador: {TEMPERATURA_LIGAR_FAN}°C")
        logger.info(f"  Nível de Log: {log_level_config.upper()}")
        return True

    except FileNotFoundError:
        if not logger.hasHandlers(): setup_logging()
        logger.error(f"Arquivo de configuração '{CONFIG_FILE}' não encontrado.")
        return False
    except json.JSONDecodeError:
        if not logger.hasHandlers(): setup_logging()
        logger.error(f"Erro ao decodificar o arquivo de configuração JSON: '{CONFIG_FILE}'. Verifique a sintaxe.")
        return False
    except Exception as e:
        if not logger.hasHandlers(): setup_logging()
        logger.error(f"Erro inesperado ao carregar configurações: {e}", exc_info=True)
        return False

def configurar_gpio():
    """Configura os pinos GPIO."""
    try:
        GPIO.setwarnings(False) # Desabilita avisos comuns do GPIO
        GPIO.setmode(GPIO.BCM)  # Usa o esquema de numeração BCM para os pinos
        GPIO.setup(FAN_PIN, GPIO.OUT) # Configura o pino do ventilador como saída
        GPIO.output(FAN_PIN, GPIO.LOW)  # Garante que o ventilador comece desligado
        logger.info(f"GPIO configurado. Pino {FAN_PIN} definido como saída e ventilador inicialmente desligado.")
    except Exception as e:
        logger.error(f"Erro ao configurar GPIO: {e}", exc_info=True)
        raise # Re-levanta a exceção para parar o script se o GPIO não puder ser configurado

def busca_sensor():
    """
    Busca pelo sensor de temperatura DS18B20 no sistema de arquivos.
    Retorna o ID do sensor se encontrado, None caso contrário.
    """
    global sensor_id # Usa a variável global sensor_id
    try:
        base_dir = '/sys/bus/w1/devices/'
        # Lista todos os diretórios que começam com '28-' (padrão para sensores DS18B20)
        for device_folder in os.listdir(base_dir):
            if device_folder.startswith('28-'):
                sensor_id = device_folder # Armazena o ID do sensor encontrado
                logger.info(f"Sensor de temperatura DS18B20 encontrado: {sensor_id}")
                return sensor_id
    except FileNotFoundError:
        logger.error(f"Diretório de dispositivos 1-Wire '{base_dir}' não encontrado. "
                     "Verifique se os módulos do kernel w1-gpio e w1-therm estão carregados.")
    except Exception as e:
        logger.error(f"Erro ao buscar sensor: {e}", exc_info=True)
    
    sensor_id = '' # Limpa o ID do sensor se não for encontrado
    return None

def ler_temperatura():
    """
    Lê a temperatura do sensor DS18B20.
    Retorna a temperatura em Celsius se a leitura for bem-sucedida, None caso contrário.
    """
    global sensor_id # Garante que estamos usando o sensor_id correto
    if not sensor_id: # Se o sensor_id não estiver definido, tenta encontrá-lo
        if not busca_sensor():
            logger.warning("Tentativa de ler temperatura, mas nenhum sensor foi encontrado.")
            return None

    device_file = f'/sys/bus/w1/devices/{sensor_id}/w1_slave'
    try:
        with open(device_file, 'r') as f:
            lines = f.readlines()
        
        # Verifica se a leitura foi bem-sucedida (deve conter "YES" na primeira linha)
        # e se a linha de temperatura está presente
        if lines[0].strip().endswith('YES') and 't=' in lines[1]:
            equals_pos = lines[1].find('t=')
            temp_string = lines[1][equals_pos+2:]
            temp_c = float(temp_string) / 1000.0
            logger.info(f"Temperatura lida do sensor {sensor_id}: {temp_c:.2f}°C")
            return temp_c
        else:
            logger.warning(f"Formato de dados inválido ou CRC não OK no arquivo do sensor: {device_file}. Conteúdo: {lines}")
            return None
    except FileNotFoundError:
        logger.error(f"Arquivo do sensor não encontrado: {device_file}. O sensor pode ter sido desconectado.")
        sensor_id = '' # Reseta o ID do sensor para tentar uma nova busca na próxima vez
        return None
    except IndexError:
        logger.error(f"Erro de formatação (IndexError) ao ler o arquivo do sensor: {device_file}. Conteúdo: {lines}")
        return None
    except Exception as e:
        logger.error(f"Erro inesperado ao ler temperatura do sensor {sensor_id}: {e}", exc_info=True)
        return None

def controlar_fan(temperatura_atual):
    """
    Controla o estado do ventilador com base na temperatura atual.
    """
    global fan_ligado # Usa a variável global que rastreia o estado do ventilador

    if temperatura_atual is None:
        logger.warning("Não foi possível controlar o ventilador: temperatura atual é desconhecida.")
        # Considerar desligar o ventilador por segurança se a leitura falhar consistentemente
        if fan_ligado:
            GPIO.output(FAN_PIN, GPIO.LOW)
            fan_ligado = False
            logger.info("Ventilador desligado por segurança devido à falha na leitura da temperatura.")
        return

    # Lógica para ligar o ventilador
    if temperatura_atual >= TEMPERATURA_LIGAR_FAN and not fan_ligado:
        try:
            GPIO.output(FAN_PIN, GPIO.HIGH)
            fan_ligado = True
            logger.info(f"Temperatura ({temperatura_atual:.2f}°C) atingiu/ultrapassou {TEMPERATURA_LIGAR_FAN:.2f}°C. LIGANDO ventilador.")
        except Exception as e:
            logger.error(f"Erro ao tentar LIGAR o ventilador: {e}", exc_info=True)
    # Lógica para desligar o ventilador
    elif temperatura_atual < TEMPERATURA_LIGAR_FAN and fan_ligado:
        try:
            GPIO.output(FAN_PIN, GPIO.LOW)
            fan_ligado = False
            logger.info(f"Temperatura ({temperatura_atual:.2f}°C) abaixo de {TEMPERATURA_LIGAR_FAN:.2f}°C. DESLIGANDO ventilador.")
        except Exception as e:
            logger.error(f"Erro ao tentar DESLIGAR o ventilador: {e}", exc_info=True)

# --- Loop Principal ---
if __name__ == "__main__":
    # Carrega as configurações. Se falhar, o script não continua.
    if not carregar_configuracoes():
        # O logger já terá sido configurado com nível padrão (INFO) se a carga falhou
        # e já terá logado o erro específico.
        logger.critical("Falha crítica ao carregar configurações. O script será encerrado.")
        print("Falha crítica ao carregar configurações. Verifique o arquivo 'monitor.log'.") # Para visibilidade se o log não for acessível
        exit(1) # Código de saída diferente de zero indica erro

    try:
        configurar_gpio() # Configura o GPIO após carregar as configurações
        logger.info("Monitor de temperatura iniciado. Pressione CTRL+C para sair.")
        
        while True:
            temperatura = ler_temperatura()
            controlar_fan(temperatura) # Controla o ventilador com base na temperatura lida
            
            # Intervalo entre as leituras de temperatura
            time.sleep(TIMER) # Espera 30 segundos

    except KeyboardInterrupt:
        logger.info("Programa encerrado manualmente (CTRL+C).")
    except Exception as e:
        # Captura qualquer outra exceção não tratada no loop principal
        logger.critical(f"Erro crítico não esperado no loop principal: {e}", exc_info=True)
        print(f"Erro crítico não esperado no loop principal:{e}. Verifique o arquivo 'monitor.log'.") # Para visibilidade se o log não for acessível
    finally:
        # Bloco finally é executado sempre, seja por saída normal, exceção ou KeyboardInterrupt
        logger.info("Iniciando limpeza de GPIO...")
        try:
            if FAN_PIN is not None: # Só tenta limpar se FAN_PIN foi definido
                 # Garante que o ventilador seja desligado ao sair
                if GPIO.gpio_function(FAN_PIN) == GPIO.OUT: # Verifica se o pino foi configurado como OUT
                    GPIO.output(FAN_PIN, GPIO.LOW)
                    logger.info(f"Ventilador no pino {FAN_PIN} desligado durante a limpeza.")
            GPIO.cleanup() # Limpa as configurações de GPIO
            logger.info("Limpeza de GPIO concluída.")
        except Exception as e:
            logger.error(f"Erro durante a limpeza de GPIO: {e}", exc_info=True)
            print(f"Erro durante a limpeza de GPIO :{e}. Verifique o arquivo 'monitor.log'.") # Para visibilidade se o log não for acessível

        
        logger.info("Monitor de temperatura finalizado.")

