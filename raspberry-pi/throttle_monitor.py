import subprocess
import time
import datetime

def get_throttled_state():
    result = subprocess.run(['vcgencmd', 'get_throttled'], stdout=subprocess.PIPE)
    state_str = result.stdout.decode().strip()
    return state_str

def log_throttled_state(state, logfile):
    with open(logfile, 'a') as f:
        current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        f.write(f"{current_time} - Throttled State: {state}\n")

def main():
    logfile = "/var/log/throttle_monitor.log"
    previous_state = None
    
    while True:
        current_state = get_throttled_state()
        
        if current_state != previous_state:
            log_throttled_state(current_state, logfile)
            previous_state = current_state
        
        time.sleep(60)  # Check every 60 seconds

if __name__ == "__main__":
    main()

