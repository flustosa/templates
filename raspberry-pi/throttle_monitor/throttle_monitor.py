#!/usr/bin/env python3
"""Monitor de subtensão/throttling do Raspberry Pi 5 -> Uptime Kuma (push monitor).

- Estado ATUAL (bits 0-3 do get_throttled): status down enquanto durar.
- Eventos curtos (2-4 s) capturados em tempo real pelo log do kernel: push down na hora,
  push up com resumo no ciclo seguinte.
- Bits "desde o boot" (16-19): só alertam quando um bit NOVO aparece.
- ping = tensão de entrada em mV -> o gráfico do Kuma vira um gráfico de tensão.
"""
import logging
import os
import re
import subprocess
import threading
import time

import requests

KUMA_HOST = os.environ["HOST_IP"].rstrip("/")  # ex.: http://100.x.y.z:3001
KUMA_TOKEN = os.environ["KUMA_TOKEN"]
INTERVAL = int(os.getenv("INTERVAL", "60"))

FLAGS = {0x1: "subtensão", 0x2: "freq. limitada", 0x4: "throttling", 0x8: "limite térmico"}

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("throttle")

lock = threading.Lock()
eventos = []  # horários de eventos do kernel ainda não resumidos


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=10, check=True).stdout.strip()


def get_throttled():
    return int(run("vcgencmd", "get_throttled").split("=")[1], 16)


def get_volts():
    m = re.search(r"=([\d.]+)V", run("vcgencmd", "pmic_read_adc", "EXT5V_V"))
    return float(m.group(1)) if m else None


def get_temp():
    with open("/sys/class/thermal/thermal_zone0/temp") as f:
        return int(f.read()) / 1000


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
    """Segue o log do kernel e reage a cada 'Undervoltag(e) detected!'."""
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
        novos = sticky & ~(last_sticky or 0) if last_sticky is not None else 0
        with lock:
            ev = eventos.copy()
            eventos.clear()

        info = f"{v:.2f} V, {c:.0f} °C" if v else f"{c:.0f} °C"
        ping = int(v * 1000) if v else None

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
