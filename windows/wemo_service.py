import pywemo
import time
import json
import os
import datetime
import requests
import sys
import ctypes # For Single Instance Lock

# --- CONFIGURATION ---
VERSION = "v4.0-Service"
MUTEX_NAME = "Global\\WemoOps_Service_Mutex_Unique_ID"

# --- PATH SETUP ---
if sys.platform == "darwin":
    APP_DATA_DIR = os.path.expanduser("~/Library/Application Support/WemoOps")
else:
    APP_DATA_DIR = os.path.join(os.getenv('APPDATA'), "WemoOps")

SCHEDULE_FILE = os.path.join(APP_DATA_DIR, "schedules.json")
SETTINGS_FILE = os.path.join(APP_DATA_DIR, "settings.json")

# --- SINGLE INSTANCE ENFORCER ---
def is_already_running():
    """
    Creates a system-wide named mutex. If it fails, another instance is running.
    """
    if sys.platform != 'win32':
        return False # Mutex logic is Windows-specific for now
        
    kernel32 = ctypes.windll.kernel32
    mutex = kernel32.CreateMutexW(None, False, MUTEX_NAME)
    last_error = kernel32.GetLastError()
    
    # ERROR_ALREADY_EXISTS = 183
    if last_error == 183:
        return True
    return False

# --- UTILS ---
def load_json(path, default_type=dict):
    if os.path.exists(path):
        try:
            with open(path) as f:
                data = json.load(f)
                if isinstance(data, default_type): return data
        except: pass
    return default_type()

def save_json(path, data):
    try:
        with open(path, 'w') as f: json.dump(data, f)
    except: pass

class SolarEngine:
    def __init__(self):
        self.lat = None
        self.lng = None
        self.solar_times = {}
        self.last_fetch = None
        
        settings = load_json(SETTINGS_FILE, dict)
        if "lat" in settings:
            self.lat = settings["lat"]
            self.lng = settings["lng"]

    def get_solar_times(self):
        today = datetime.date.today()
        if self.last_fetch == today and self.solar_times: return self.solar_times
        if not self.lat: return None

        try:
            url = f"https://api.sunrise-sunset.org/json?lat={self.lat}&lng={self.lng}&formatted=0"
            r = requests.get(url, timeout=10)
            data = r.json()
            if data["status"] == "OK":
                res = data["results"]
                def to_local(utc_str):
                    # Fixed Timezone Math
                    dt_utc = datetime.datetime.fromisoformat(utc_str)
                    dt_local = dt_utc.astimezone()
                    return dt_local.strftime("%H:%M")

                self.solar_times = {
                    "sunrise": to_local(res["sunrise"]),
                    "sunset": to_local(res["sunset"])
                }
                self.last_fetch = today
                return self.solar_times
        except: pass
        return None

# --- MAIN SERVICE LOOP ---
def run_service():
    # 1. CHECK SINGLE INSTANCE
    if is_already_running():
        print("Another instance is already running. Quitting.")
        sys.exit(0)

    print(f"Wemo Ops Service {VERSION} Started...")
    solar = SolarEngine()
    known_devices = {}

    # Initial Scan
    try:
        devices = pywemo.discover_devices()
        for d in devices: known_devices[d.name] = d
    except: pass

    while True:
        try:
            schedules = load_json(SCHEDULE_FILE, list)
            
            now = datetime.datetime.now()
            today_str = now.strftime("%Y-%m-%d")
            weekday = now.weekday()
            current_hhmm = now.strftime("%H:%M")
            solar_data = solar.get_solar_times()

            for job in schedules:
                if weekday not in job['days']: continue
                
                trigger_time = ""
                if job['type'] == "Time (Fixed)":
                    trigger_time = job['value']
                elif solar_data:
                    base_str = solar_data['sunrise'] if job['type'] == "Sunrise" else solar_data['sunset']
                    try:
                        dt = datetime.datetime.strptime(f"{today_str} {base_str}", "%Y-%m-%d %H:%M")
                        offset_mins = int(job['value']) * job['offset_dir']
                        trigger_dt = dt + datetime.timedelta(minutes=offset_mins)
                        trigger_time = trigger_dt.strftime("%H:%M")
                    except: continue

                if trigger_time == current_hhmm and job.get('last_run') != today_str:
                    
                    if job['device'] not in known_devices:
                        try:
                            devs = pywemo.discover_devices()
                            for d in devs: known_devices[d.name] = d
                        except: pass

                    if job['device'] in known_devices:
                        dev = known_devices[job['device']]
                        try:
                            if job['action'] == "Turn ON": dev.on()
                            elif job['action'] == "Turn OFF": dev.off()
                            elif job['action'] == "Toggle": dev.toggle()
                            
                            job['last_run'] = today_str
                            save_json(SCHEDULE_FILE, schedules)
                        except: pass
        except: pass
        
        time.sleep(30)

if __name__ == "__main__":
    run_service()