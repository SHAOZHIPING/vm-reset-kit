# -*- coding: utf-8 -*-
"""Windows 设备指纹实验工具（软件层 / 可恢复）"""
from __future__ import annotations
import os, subprocess, sys, traceback
from pathlib import Path
APP_NAME = "Windows 设备指纹实验工具（软件层 / 可恢复）"
APP_VERSION = "1.1.0"
PS1_NAME = "Apply-NewSoftwareIdentity.ps1"

def app_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent

def message_box(text: str, title: str, flags: int = 0x10) -> int:
    if sys.platform == "win32":
        import ctypes
        return ctypes.windll.user32.MessageBoxW(None, text, title, flags)
    print(f"{title}: {text}")
    return 0

def is_admin() -> bool:
    if sys.platform != "win32":
        return False
    import ctypes
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False

def require_env() -> None:
    if sys.platform != "win32":
        message_box("本工具只能在 Windows 上运行。", "无法启动"); sys.exit(1)
    if sys.maxsize <= 2**32:
        message_box("必须使用 64 位 Python。", "无法启动"); sys.exit(1)
    if not is_admin():
        message_box("需要管理员权限。请右键以管理员身份运行。", "需要管理员权限")
        sys.exit(1)

def powershell_exe() -> str:
    p = Path(os.environ.get("WINDIR", r"C:\Windows")) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"
    return str(p) if p.exists() else "powershell.exe"

def run_ps1(*args: str, timeout: int = 180):
    script = app_dir() / PS1_NAME
    if not script.exists():
        raise FileNotFoundError(f"找不到 {script}")
    cmd = [powershell_exe(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), *args]
    flags = 0x08000000 if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace", creationflags=flags)

def main() -> None:
    require_env()
    import tkinter as tk
    from tkinter import messagebox, scrolledtext
    root = tk.Tk(); root.title(APP_NAME); root.geometry("860x680")
    tk.Label(root, text="建议只在虚拟机使用。硬件身份用宿主机脚本。", bg="#8B0000", fg="white", wraplength=820, padx=10, pady=8).pack(fill="x")
    status = tk.StringVar(value="就绪")
    tk.Label(root, textvariable=status, anchor="w", padx=10).pack(fill="x")
    text = scrolledtext.ScrolledText(root, font=("Consolas", 10), wrap="word")
    text.pack(fill="both", expand=True, padx=10, pady=8)
    def set_text(body):
        text.configure(state="normal"); text.delete("1.0", "end"); text.insert("end", body); text.configure(state="disabled")
    def refresh():
        status.set("正在读取..."); root.update_idletasks()
        r = run_ps1("-ShowOnly", timeout=90)
        body = (r.stdout or "") + (("\n"+r.stderr) if r.stderr else "")
        set_text(body); status.set("就绪")
    def on_apply():
        if not messagebox.askokcancel("确认伪装", "将生成并写入新的软件层身份。确定？"): return
        r = run_ps1("-Auto", "-Force", timeout=180)
        if r.returncode != 0: messagebox.showerror("失败", (r.stdout or "")+(r.stderr or ""))
        else: messagebox.showinfo("完成", "软件层新身份已写入。")
        refresh()
    def on_restore():
        if not messagebox.askokcancel("确认恢复", "从 original_backup.json 恢复。确定？"): return
        r = run_ps1("-Restore", timeout=180)
        if r.returncode != 0: messagebox.showerror("失败", (r.stdout or "")+(r.stderr or ""))
        else: messagebox.showinfo("完成", "已恢复，请重启。")
        refresh()
    bar = tk.Frame(root); bar.pack(fill="x", padx=10, pady=(0,10))
    tk.Button(bar, text="生成并应用新伪装设备配置", command=on_apply, height=2, bg="#1F4E79", fg="white").pack(side="left", expand=True, fill="x", padx=(0,6))
    tk.Button(bar, text="一键恢复原始真实设备", command=on_restore, height=2, bg="#7F6000", fg="white").pack(side="left", expand=True, fill="x", padx=(6,0))
    if not messagebox.askokcancel("实验用途确认", "仅用于自有虚拟机实验。点确定继续。"):
        root.destroy(); sys.exit(0)
    root.after(200, refresh); root.mainloop()

if __name__ == "__main__":
    main()
