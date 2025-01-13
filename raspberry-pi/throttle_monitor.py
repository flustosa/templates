import datetime
import http.client
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

def gatus_push(status):
    host = "10.11.12.163"
    port = "8080"
    url = f"/api/v1/endpoints/core_pi-throttle/external?success={status}"
    token = f'Bearer {os.getenv("GATUS_TOKEN")}'
    conn = http.client.HTTPConnection(host, port, timeout=10)
    header = {"Host": host, "Authorization": token}
    conn.request("POST", url, headers=header)
    response = conn.getresponse()


def main():

    previous_state = None
    
    while True:
        current_state = get_throttled_state()
        print(f'current_state: {current_state}')
        log_throttled_state(current_state)
        if current_state != 'throttled=0x0':
            log_throttled_state(current_state)
            status = 'false'
            previous_state = current_state
        else:
            status = 'true'
        try:
            gatus_push(status)
        except Exception as e:
            log_throttled_state(e)

        
        time.sleep(300)  # Check every 300 seconds


if __name__ == "__main__":
    main()

