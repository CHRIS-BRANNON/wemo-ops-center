import customtkinter as ctk
import pywemo
import threading
import sys
import os
from tkinter import messagebox
import pyperclip

# --- CONFIGURATION ---
VERSION = "v2.0"

# --- PYINSTALLER RESOURCE PATH FIX ---
# This allows the app to find bundled files (like openssl.exe) if you ever build it as a single file.
if getattr(sys, 'frozen', False):
    os.environ['PATH'] += os.pathsep + sys._MEIPASS

ctk.set_appearance_mode("Dark")
ctk.set_default_color_theme("dark-blue")

class WemoOpsApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title(f"Wemo Ops Center {VERSION} | Production")
        self.geometry("900x650")
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        # --- Sidebar ---
        self.sidebar = ctk.CTkFrame(self, width=200, corner_radius=0)
        self.sidebar.grid(row=0, column=0, sticky="nsew")
        
        self.logo = ctk.CTkLabel(self.sidebar, text="WEMO OPS", font=("Arial Black", 20))
        self.logo.pack(pady=20)
        
        self.btn_dash = ctk.CTkButton(self.sidebar, text="  Dashboard", anchor="w", command=lambda: self.show_tab("dash"))
        self.btn_dash.pack(pady=5, padx=10, fill="x")
        
        self.btn_prov = ctk.CTkButton(self.sidebar, text="  Provisioner", anchor="w", fg_color="#444", command=lambda: self.show_tab("prov"))
        self.btn_prov.pack(pady=5, padx=10, fill="x")
        
        ctk.CTkLabel(self.sidebar, text=f"{VERSION} Stable", text_color="gray", font=("Arial", 10)).pack(side="bottom", pady=10)

        # --- Main Area ---
        self.main_area = ctk.CTkFrame(self, corner_radius=0, fg_color="transparent")
        self.main_area.grid(row=0, column=1, sticky="nsew", padx=20, pady=20)

        self.frames = {}
        self.create_dashboard()
        self.create_provisioner()

        self.show_tab("prov")
        self.refresh_network()

    # ---------------------------------------------------------
    # UI CONSTRUCTION
    # ---------------------------------------------------------
    def create_dashboard(self):
        frame = ctk.CTkFrame(self.main_area, fg_color="transparent")
        self.frames["dash"] = frame
        head = ctk.CTkFrame(frame, fg_color="transparent")
        head.pack(fill="x", pady=(0, 20))
        ctk.CTkLabel(head, text="Network Overview", font=("Roboto", 24)).pack(side="left")
        ctk.CTkButton(head, text="↻ Refresh Scan", width=120, command=self.refresh_network).pack(side="right")
        self.dev_list = ctk.CTkScrollableFrame(frame, label_text="Discovered Devices")
        self.dev_list.pack(fill="both", expand=True)

    def create_provisioner(self):
        frame = ctk.CTkFrame(self.main_area, fg_color="transparent")
        self.frames["prov"] = frame
        ctk.CTkLabel(frame, text="Device Provisioning", font=("Roboto", 24)).pack(anchor="w", pady=(0, 20))
        
        info = ctk.CTkFrame(frame, fg_color="#222")
        info.pack(fill="x", pady=10)
        ctk.CTkLabel(info, text="1. Connect PC to 'Wemo.Mini.XXX'\n2. Enter Home Wi-Fi details below\n3. Click Push Config", 
                     justify="left", font=("Consolas", 14), padx=10, pady=10).pack(anchor="w")

        self.ssid_entry = ctk.CTkEntry(frame, placeholder_text="SSID (WiFi Name)")
        self.ssid_entry.pack(fill="x", pady=10)
        self.pass_entry = ctk.CTkEntry(frame, placeholder_text="Password", show="*")
        self.pass_entry.pack(fill="x", pady=10)
        
        self.prov_btn = ctk.CTkButton(frame, text="Push Configuration", fg_color="#28a745", hover_color="#1e7e34", height=50, command=self.run_provision_thread)
        self.prov_btn.pack(fill="x", pady=20)
        
        self.prov_log = ctk.CTkTextbox(frame, height=250, font=("Consolas", 12))
        self.prov_log.pack(fill="x")

    def show_tab(self, name):
        for key, frame in self.frames.items(): frame.pack_forget()
        self.frames[name].pack(fill="both", expand=True)

    def log_prov(self, msg):
        self.prov_log.insert("end", f"{msg}\n")
        self.prov_log.see("end")

    # ---------------------------------------------------------
    # PROVISIONING LOGIC (Standard PyWemo Wrapper)
    # ---------------------------------------------------------
    def run_provision_thread(self):
        ssid = self.ssid_entry.get()
        pwd = self.pass_entry.get()
        
        if not ssid: 
            messagebox.showwarning("Missing Data", "Please enter a Wi-Fi SSID.")
            return

        self.prov_btn.configure(state="disabled", text="Running...")
        self.prov_log.delete("1.0", "end")
        threading.Thread(target=self._provision_task, args=(ssid, pwd), daemon=True).start()

    def _provision_task(self, ssid, pwd):
        self.log_prov("--- Wemo Provisioning Tool ---")
        self.log_prov(f"Targeting SSID: {ssid}")
        
        target_ips = ["192.168.49.1", "10.22.22.1", "192.168.1.1"]
        dev = None

        # 1. Discovery Loop
        for ip in target_ips:
            self.log_prov(f"Probing {ip}...")
            try:
                url = pywemo.setup_url_for_address(ip)
                dev = pywemo.discovery.device_from_description(url)
                if dev:
                    self.log_prov(f"SUCCESS: Found {dev.name} at {ip}")
                    break
            except Exception:
                continue
        
        if not dev:
            self.log_prov("\nERROR: Device not found. Ensure you are connected to the 'Wemo.Mini.XXX' Wi-Fi.")
            self.prov_btn.configure(state="normal", text="Push Configuration")
            return

        # 2. Injection
        self.log_prov("Injecting Wi-Fi credentials...")
        try:
            dev.setup(ssid=ssid, password=pwd)
            self.log_prov("Payload sent! The device will now reboot and join your network.")
            self.log_prov("Wait 60s, switch your Wi-Fi back to Home, and check the Dashboard.")
        except Exception as e:
            self.log_prov(f"Error sending payload: {e}")

        self.prov_btn.configure(state="normal", text="Push Configuration")

    # ---------------------------------------------------------
    # DASHBOARD
    # ---------------------------------------------------------
    def refresh_network(self):
        for w in self.dev_list.winfo_children(): w.destroy()
        ctk.CTkLabel(self.dev_list, text="Scanning...", text_color="yellow").pack(pady=20)
        threading.Thread(target=self._scan_thread, daemon=True).start()

    def _scan_thread(self):
        try:
            devices = pywemo.discover_devices()
            self.after(0, self.update_dashboard, devices)
        except: pass

    def update_dashboard(self, devices):
        for w in self.dev_list.winfo_children(): w.destroy()
        if not devices: ctk.CTkLabel(self.dev_list, text="No devices found.").pack(pady=20)
        for dev in devices: self.build_device_card(dev)

    def build_device_card(self, dev):
        try: mac = getattr(dev, 'mac', "Unknown")
        except: mac = "Unknown"
        try: fw = getattr(dev, 'firmware_version', "Unknown")
        except: fw = "Unknown"
        try: model = getattr(dev, 'model_name', "Unknown")
        except: model = "Unknown"
        
        card = ctk.CTkFrame(self.dev_list, fg_color="#1a1a1a")
        card.pack(fill="x", pady=5, padx=5)
        top = ctk.CTkFrame(card, fg_color="transparent")
        top.pack(fill="x", padx=10, pady=10)
        ctk.CTkLabel(top, text="⚡", font=("Arial", 20)).pack(side="left", padx=(0,10))
        ctk.CTkLabel(top, text=f"{dev.name}", font=("Roboto", 16, "bold")).pack(side="left")
        
        def toggle(): threading.Thread(target=dev.toggle, daemon=True).start()
        switch = ctk.CTkSwitch(top, text="Power", command=toggle)
        switch.pack(side="right")
        try: 
            if dev.get_state(): switch.select()
        except: pass

        info_text = f"IP: {dev.host}  |  MAC: {mac}  |  FW: {fw}"
        bot = ctk.CTkFrame(card, fg_color="#111")
        bot.pack(fill="x", padx=10, pady=(0, 10))
        ctk.CTkLabel(bot, text=info_text, font=("Consolas", 11), text_color="#aaa").pack(side="left", padx=10, pady=5)
        
        def extract_hk():
            threading.Thread(target=self._extract_hk_task, args=(dev,), daemon=True).start()
        ctk.CTkButton(bot, text="Get HomeKit Code", width=120, height=20, font=("Arial", 10), 
                      fg_color="#555", hover_color="#666", command=extract_hk).pack(side="right", padx=5)

    def _extract_hk_task(self, dev):
        try:
            if hasattr(dev, 'basicevent'):
                data = dev.basicevent.GetHKSetupInfo()
                code = data.get('HKSetupCode')
                if code:
                    self.after(0, lambda: messagebox.showinfo("Code Found", f"HomeKit Code:\n\n{code}"))
                    pyperclip.copy(code)
                else:
                    self.after(0, lambda: messagebox.showwarning("Not Found", "No HomeKit data found."))
            else:
                self.after(0, lambda: messagebox.showerror("Error", "Unsupported Device."))
        except Exception as e:
             self.after(0, lambda: messagebox.showerror("Failed", f"Error: {e}"))

if __name__ == "__main__":
    app = WemoOpsApp()
    app.mainloop()