import datetime
import requests
import os
import subprocess
import time

def get_throttled_state():
    result = subprocess.run(['vcgencmd', 'get_throttled'], stdout=subprocess.PIPE)
    state_str = result.stdout.decode().strip()
    return state_str

def log_throttled_state(state):
    current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_message = f"{current_time} - Throttled State: {state}"
    subprocess.run(['logger', log_message])

def uptime_push(status, msg):
    host = os.getenv("HOST_IP")
    token = os.getenv("KUMA_TOKEN")
    url = f"/api/push/{token}?status={status}&msg={msg}&ping=" # Uptime Kuma
    request = requests.get(f"{host}{url}")


def main():

    previous_state = None
    
    while True:
        current_state = get_throttled_state()
        print(f'current_state: {current_state}')
        log_throttled_state(current_state)
        if current_state != 'throttled=0x0':
            log_throttled_state(current_state)
            status = 'down'
            msg = 'throttled'
            previous_state = current_state
        else:
            status = 'up'
            msg = "OK"
            print(status)
        try:
            uptime_push(status, msg)
        except Exception as e:
            log_throttled_state(e)

        
        time.sleep(300)  # Check every 300 seconds


if __name__ == "__main__":
    main()


