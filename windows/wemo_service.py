import pywemo
import time
import json
import os
import datetime
import requests
import sys

# --- PATH SETUP ---
if sys.platform == "darwin":
    APP_DATA_DIR = os.path.expanduser("~/Library/Application Support/WemoOps")
else:
    APP_DATA_DIR = os.path.join(os.getenv('APPDATA'), "WemoOps")

SCHEDULE_FILE = os.path.join(APP_DATA_DIR, "schedules.json")
SETTINGS_FILE = os.path.join(APP_DATA_DIR, "settings.json")

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
        
        # Load cached location
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
                    dt_utc = datetime.datetime.fromisoformat(utc_str)
                    now_timestamp = time.time()
                    offset = datetime.datetime.fromtimestamp(now_timestamp) - datetime.datetime.utcfromtimestamp(now_timestamp)
                    dt_local = dt_utc + offset
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
    print("Wemo Ops Service Started...")
    solar = SolarEngine()
    known_devices = {}

    # Initial Scan
    try:
        devices = pywemo.discover_devices()
        for d in devices: known_devices[d.name] = d
    except: pass

    while True:
        try:
            # 1. Reload Schedules (Hot-Reload)
            schedules = load_json(SCHEDULE_FILE, list)
            
            # 2. Get Environment
            now = datetime.datetime.now()
            today_str = now.strftime("%Y-%m-%d")
            weekday = now.weekday()
            current_hhmm = now.strftime("%H:%M")
            solar_data = solar.get_solar_times()

            # 3. Check Jobs
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

                # Fire Condition
                if trigger_time == current_hhmm and job.get('last_run') != today_str:
                    print(f"Firing {job['action']} on {job['device']}")
                    
                    # Discover device if missing
                    if job['device'] not in known_devices:
                        try:
                            devices = pywemo.discover_devices()
                            for d in devices: known_devices[d.name] = d
                        except: pass

                    if job['device'] in known_devices:
                        dev = known_devices[job['device']]
                        try:
                            if job['action'] == "Turn ON": dev.on()
                            elif job['action'] == "Turn OFF": dev.off()
                            elif job['action'] == "Toggle": dev.toggle()
                            
                            # Mark complete
                            job['last_run'] = today_str
                            save_json(SCHEDULE_FILE, schedules)
                        except: pass
        except Exception as e:
            print(f"Service Error: {e}")
        
        # Deep Sleep
        time.sleep(30)

if __name__ == "__main__":
    run_service()