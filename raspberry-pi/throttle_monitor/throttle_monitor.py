#!/usr/bin/env python3
"""Monitor de subtensão/throttling do Raspberry Pi -> Uptime Kuma (push monitor).

Hardware: aplicável e testado APENAS em
  - Raspberry Pi 4 Model B
  - Raspberry Pi 5 Model B
O modelo é detectado em /proc/device-tree/model; em qualquer outro hardware o
script encerra com código 3 (o systemd não reinicia: RestartPreventExitStatus=3).

Funcionamento (igual nos dois modelos):
- Estado ATUAL (bits 0-3 do get_throttled): status down enquanto durar.
- Eventos curtos (2-4 s) capturados em tempo real pelo log do kernel
  ("Undervoltage detected!" do driver raspberrypi-hwmon): push down na hora,
  push up com resumo no ciclo seguinte.
- Bits "desde o boot" (16-19): só alertam quando um bit NOVO aparece.
- ping = métrica numérica para o gráfico do Kuma (PING_METRIC):
    volt  -> tensão de entrada em mV (só existe sensor no Pi 5; no Pi 4 não envia ping)
    temp  -> temperatura do SoC em décimos de °C (funciona nos dois)

Diferenças entre os modelos tratadas aqui:
- Pi 5: tensão de entrada via `vcgencmd pmic_read_adc EXT5V_V`.
- Pi 4: não tem sensor de tensão de entrada (o PMIC não expõe EXT5V);
        a mensagem mostra "V n/d". get_throttled, temperatura e log do
        kernel são iguais aos do Pi 5.
"""
import logging
import os
import re
import subprocess
import sys
import threading
import time

import requests

KUMA_HOST = os.environ["HOST_IP"].rstrip("/")  # ex.: http://100.x.y.z:3001
KUMA_TOKEN = os.environ["KUMA_TOKEN"]
INTERVAL = int(os.getenv("INTERVAL", "60"))
PING_METRIC = os.getenv("PING_METRIC", "volt").lower()  # volt | temp

FLAGS = {0x1: "subtensão", 0x2: "freq. limitada", 0x4: "throttling", 0x8: "limite térmico"}
EXIT_HW_NAO_SUPORTADO = 3

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("throttle")

lock = threading.Lock()
eventos = []  # horários de eventos do kernel ainda não resumidos


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=10, check=True).stdout.strip()


# ---------- detecção de hardware ----------

def detect_model():
    try:
        with open("/proc/device-tree/model") as f:
            model = f.read().rstrip("\x00").strip()
    except OSError:
        model = "desconhecido"
    m = re.search(r"Raspberry Pi ([45]) Model B", model)
    if not m:
        log.error("Hardware não suportado: %s (apenas Pi 4 e Pi 5 Model B)", model)
        sys.exit(EXIT_HW_NAO_SUPORTADO)
    return int(m.group(1)), model


# ---------- leituras ----------

def get_throttled():  # Pi 4 e Pi 5
    return int(run("vcgencmd", "get_throttled").split("=")[1], 16)


def get_temp():  # Pi 4 e Pi 5
    with open("/sys/class/thermal/thermal_zone0/temp") as f:
        return int(f.read()) / 1000


def get_volts_pi5():
    m = re.search(r"=([\d.]+)V", run("vcgencmd", "pmic_read_adc", "EXT5V_V"))
    return float(m.group(1)) if m else None


def get_volts_pi4():
    return None  # sem sensor de tensão de entrada


VOLT_READERS = {4: get_volts_pi4, 5: get_volts_pi5}


# ---------- Kuma ----------

def decode(bits):
    return ", ".join(nome for b, nome in FLAGS.items() if bits & b) or "nenhum"


def push(status, msg, ping=None):
    params = {"status": status, "msg": msg[:250]}
    if ping is not None:
        params["ping"] = ping
    try:
        r = requests.get(f"{KUMA_HOST}/api/push/{KUMA_TOKEN}", params=params, timeout=10)
        r.raise_for_status()
    except requests.RequestException as e:
        log.warning("push para o Kuma falhou: %s", e)


def follow_kernel():
    """Segue o log do kernel e reage a cada 'Undervoltag(e) detected!' (Pi 4 e Pi 5)."""
    p = subprocess.Popen(
        ["journalctl", "-k", "-f", "-n", "0", "-o", "cat"],
        stdout=subprocess.PIPE, text=True,
    )
    for line in p.stdout:
        if re.search(r"undervolt", line, re.I):
            ts = time.strftime("%d/%m %H:%M:%S")
            log.warning("kernel: %s", line.strip())
            with lock:
                eventos.append(ts)
            push("down", f"Subtensão detectada em {ts}")
    log.error("journalctl encerrou; reiniciando o serviço")
    os._exit(1)  # o systemd reinicia (Restart=always)


def main():
    versao, model = detect_model()
    get_volts = VOLT_READERS[versao]
    log.info("Hardware: %s | INTERVAL=%ss | PING_METRIC=%s", model, INTERVAL, PING_METRIC)
    if versao == 4 and PING_METRIC == "volt":
        log.info("Pi 4 sem sensor de tensão: ping não será enviado (use PING_METRIC=temp)")

    threading.Thread(target=follow_kernel, daemon=True).start()
    last_sticky = None
    last_status = None

    while True:
        try:
            t = get_throttled()
            v = get_volts()
            c = get_temp()
        except Exception as e:
            log.error("falha de leitura: %s", e)
            push("down", f"Erro de leitura: {e}")
            time.sleep(INTERVAL)
            continue

        agora = t & 0xF
        sticky = (t >> 16) & 0xF
        novos = sticky & ~last_sticky if last_sticky is not None else 0
        with lock:
            ev = eventos.copy()
            eventos.clear()

        volt_txt = f"{v:.2f} V" if v is not None else "V n/d"
        info = f"{volt_txt}, {c:.0f} °C"
        if PING_METRIC == "temp":
            ping = int(c * 1) # Temperatura com duas casas decimais, para exibição correta no gráfico do Uptime Kuma
        else:
            ping = int(v * 1000) if v is not None else None

        if agora:
            status, msg = "down", f"ATIVO: {decode(agora)} | {info}"
        elif novos and not ev:
            # algo que não passou pelo log do kernel (ex.: limite térmico)
            status, msg = "down", f"Nova ocorrência (firmware): {decode(novos)} | {info}"
        elif ev:
            status, msg = "up", f"Normalizado. Eventos: {', '.join(ev)} | {info}"
        else:
            status, msg = "up", f"OK | {info} | desde o boot: {decode(sticky)}"

        push(status, msg, ping)
        if status != last_status or ev or novos:  # loga só mudanças
            log.info("%s: %s (raw=%s)", status, msg, hex(t))
        last_status, last_sticky = status, sticky
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
