#!/usr/bin/env python3
"""
Hermes Cloud - Human Takeover Helper
====================================
实现 Grok-bot / Claude Computer Use 风格的远程接管卡片交互：
1. 抓取当前 X11 桌面最新画面 (:1)
2. 单向向 Telegram 发送带截图与 Inline Keyboard 的交互卡片（带直达链接与操作按钮）
3. 记录接管状态，无额外长轮询占用
4. 收到回调后通过 editMessageCaption 原地更新消息状态并移除所有按钮（防二次点击）
"""

import os
import sys
import json
import time
import subprocess
import urllib.request
import urllib.parse
from pathlib import Path

STATE_FILE = Path("/root/.hermes/takeover_state.json")


def get_env_var(key: str, default: str = "") -> str:
    val = os.environ.get(key, "")
    if val:
        return val
    # 尝试从 /root/.hermes/.env 读取
    env_file = Path("/root/.hermes/.env")
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith(f"{key}="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    return default


def get_public_ip() -> str:
    """尝试快速获取公网 IP"""
    for endpoint in ["https://api.ipify.org", "http://ifconfig.me/ip", "https://icanhazip.com"]:
        try:
            req = urllib.request.Request(endpoint, headers={"User-Agent": "curl/7.68.0"})
            with urllib.request.urlopen(req, timeout=2) as resp:
                ip = resp.read().decode("utf-8").strip()
                if ip and "." in ip:
                    return ip
        except Exception:
            continue
    return ""


def get_safe_desktop_url() -> str:
    """获取安全的 Web 桌面直达链接（严格防止 localhost 触发 Telegram 400）"""
    url = get_env_var("REMOTE_DESKTOP_URL", "")
    public_host = get_env_var("PUBLIC_HOST", "")
    
    # 若配置了 PUBLIC_HOST 且 URL 中包含 localhost，直接替换
    if public_host and ("localhost" in url or "127.0.0.1" in url or not url):
        url = f"https://{public_host}:8444"
        return url

    # 若未指定有效 URL 或依然包含 localhost，尝试探测公网 IP
    if not url or "localhost" in url or "127.0.0.1" in url:
        pub_ip = get_public_ip()
        if pub_ip:
            url = f"https://{pub_ip}:8444"
        else:
            url = ""
            
    return url


def get_telegram_chat_id() -> str:
    chat_id = get_env_var("TELEGRAM_HOME_CHANNEL")
    if not chat_id:
        allowed = get_env_var("TELEGRAM_ALLOWED_USERS")
        if allowed:
            chat_id = allowed.split(",")[0].strip()
    return chat_id


def capture_desktop_screenshot(output_path: str = "/tmp/takeover_screen.png") -> str:
    """
    极速多后端截屏引擎（默认 DISPLAY=:1）：
    1. Python-Xlib + PIL（毫秒级原生内存抓屏，零外部进程依赖）
    2. scrot CLI
    3. ImageMagick import
    """
    display_str = os.environ.get("DISPLAY", ":1")
    os.environ["DISPLAY"] = display_str

    # 后端 1: Python-Xlib + Pillow (极速且最稳定)
    try:
        from Xlib import display, X
        from PIL import Image

        d = display.Display(display_str)
        screen = d.screen()
        root = screen.root
        width = screen.width_in_pixels
        height = screen.height_in_pixels

        raw = root.get_image(0, 0, width, height, X.ZPixmap, 0xffffffff)
        image = Image.frombytes("RGB", (width, height), raw.data, "raw", "BGRX")
        image.save(output_path, "PNG", optimize=True)
        d.close()
        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            return output_path
    except Exception:
        pass

    # 后端 2: scrot
    try:
        res = subprocess.run(["scrot", "-z", "-q", "80", "-o", output_path], check=False, capture_output=True)
        if res.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            return output_path
    except Exception:
        pass

    # 后端 3: import (ImageMagick)
    try:
        res = subprocess.run(["import", "-window", "root", output_path], check=False, capture_output=True)
        if res.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            return output_path
    except Exception:
        pass

    return ""


def send_telegram_photo(token: str, chat_id: str, photo_path: str, caption: str, reply_markup: dict) -> dict:
    """通过 Telegram Bot API 发送图片及内联键盘 (multipart/form-data)"""
    url = f"https://api.telegram.org/bot{token}/sendPhoto"
    boundary = f"----WebKitFormBoundary{int(time.time() * 1000)}"
    
    body = bytearray()
    
    def add_field(name: str, value: str):
        nonlocal body
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"))
        body.extend(f"{value}\r\n".encode("utf-8"))

    add_field("chat_id", str(chat_id))
    add_field("caption", caption)
    add_field("parse_mode", "HTML")
    if reply_markup:
        add_field("reply_markup", json.dumps(reply_markup, ensure_ascii=False))

    if photo_path and os.path.exists(photo_path):
        filename = os.path.basename(photo_path)
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(f'Content-Disposition: form-data; name="photo"; filename="{filename}"\r\n'.encode("utf-8"))
        body.extend(b"Content-Type: image/png\r\n\r\n")
        with open(photo_path, "rb") as f:
            body.extend(f.read())
        body.extend(b"\r\n")

    body.extend(f"--{boundary}--\r\n".encode("utf-8"))

    req = urllib.request.Request(url, data=bytes(body))
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_detail = e.read().decode("utf-8") if e.fp else str(e)
        return {"ok": False, "error_code": e.code, "description": f"HTTP {e.code}: {error_detail}"}


def edit_telegram_caption(token: str, chat_id: str, message_id: int, caption: str, reply_markup: dict = None) -> dict:
    """通过 Telegram editMessageCaption 原地更新卡片文字并清除按钮"""
    url = f"https://api.telegram.org/bot{token}/editMessageCaption"
    payload = {
        "chat_id": chat_id,
        "message_id": message_id,
        "caption": caption,
        "parse_mode": "HTML",
        "reply_markup": reply_markup or {"inline_keyboard": []}
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_detail = e.read().decode("utf-8") if e.fp else str(e)
        return {"ok": False, "description": f"HTTP {e.code}: {error_detail}"}


def answer_telegram_callback(token: str, callback_query_id: str, text: str = "已确认") -> dict:
    """应答 Callback Query，弹出轻量 Toast"""
    url = f"https://api.telegram.org/bot{token}/answerCallbackQuery"
    payload = {
        "callback_query_id": callback_query_id,
        "text": text,
        "show_alert": False
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return {}


def request_human_takeover(reason: str) -> dict:
    """
    触发人类接管卡片：
    1. 截取最新桌面
    2. 发送带 [Take over], [I'm done], [Skip] 的卡片
    3. 记录状态到 takeover_state.json 并退出
    """
    token = get_env_var("TELEGRAM_BOT_TOKEN")
    chat_id = get_telegram_chat_id()
    desktop_url = get_safe_desktop_url()

    if not token or not chat_id:
        return {
            "status": "error",
            "message": "TELEGRAM_BOT_TOKEN 或 TELEGRAM_ALLOWED_USERS 未配置，无法发送 Telegram 卡片。"
        }

    screenshot_path = capture_desktop_screenshot()
    action_id = f"tk_{int(time.time())}"

    caption = f"<b>Computer</b>        ✳️ <i>Action needed</i>\n\n{reason}"

    inline_keyboard = []
    if desktop_url:
        inline_keyboard.append([{"text": "Take over", "url": desktop_url}])
    
    inline_keyboard.append([
        {"text": "I'm done", "callback_data": f"takeover:done:{action_id}"},
        {"text": "Skip", "callback_data": f"takeover:skip:{action_id}"}
    ])

    reply_markup = {"inline_keyboard": inline_keyboard}

    try:
        resp = send_telegram_photo(token, chat_id, screenshot_path, caption, reply_markup)
        if resp.get("ok"):
            msg_id = resp["result"]["message_id"]
            
            # 保存状态
            STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
            state_data = {
                "action_id": action_id,
                "chat_id": chat_id,
                "message_id": msg_id,
                "reason": reason,
                "status": "pending",
                "desktop_url": desktop_url,
                "created_at": time.time()
            }
            STATE_FILE.write_text(json.dumps(state_data, ensure_ascii=False, indent=2), encoding="utf-8")

            return {
                "status": "success",
                "message": "Takeover card displayed. Please stay completely silent and wait for the user to click the button on Telegram.",
                "action_id": action_id,
                "message_id": msg_id
            }
        else:
            return {"status": "error", "message": f"Telegram API 错误: {resp.get('description', resp)}"}
    except Exception as e:
        return {"status": "error", "message": f"发送接管卡片失败: {str(e)}"}


def resolve_takeover(action_id: str = None, action: str = "done", callback_query_id: str = None) -> dict:
    """
    完成或跳过接管：
    1. 应答 callback query
    2. 原地编辑 Telegram 消息 Caption
    3. 移除全部按钮（防二次点击）
    4. 更新状态文件
    """
    token = get_env_var("TELEGRAM_BOT_TOKEN")
    if not token or not STATE_FILE.exists():
        return {"status": "error", "message": "状态文件或 Token 不存在"}

    try:
        state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except Exception as e:
        return {"status": "error", "message": f"读取状态文件失败: {str(e)}"}

    if action_id and state.get("action_id") != action_id:
        # 如果指定了 action_id 且不匹配，仍尝试处理
        pass

    chat_id = state.get("chat_id")
    message_id = state.get("message_id")
    reason = state.get("reason", "远程桌面操作")

    # 1. 弹出轻提示
    if callback_query_id:
        try:
            toast_text = "✅ 已确认接管完成，Hermes 正在继续..." if action == "done" else "⏭️ 已跳过接管"
            answer_telegram_callback(token, callback_query_id, toast_text)
        except Exception:
            pass

    # 2. 原地更新 Caption 并移除所有按钮
    if action == "done":
        new_caption = f"<b>Computer</b>        ✅ <i>Takeover Completed</i>\n\n{reason}"
    else:
        new_caption = f"<b>Computer</b>        ⏭️ <i>Skipped</i>\n\n{reason}"

    try:
        edit_telegram_caption(token, chat_id, message_id, new_caption, reply_markup={"inline_keyboard": []})
        state["status"] = "completed" if action == "done" else "skipped"
        state["resolved_at"] = time.time()
        STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
        return {"status": "success", "message": f"卡片已原地更新为【{state['status']}】并已移除按钮"}
    except Exception as e:
        return {"status": "error", "message": f"更新 Telegram 卡片失败: {str(e)}"}


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: takeover_helper.py <request|resolve|resolve_latest> [args...]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "request":
        reason_arg = sys.argv[2] if len(sys.argv) > 2 else "需要人类协助操作远程桌面"
        res = request_human_takeover(reason_arg)
        print(json.dumps(res, ensure_ascii=False, indent=2))
    elif cmd == "resolve":
        act_id = sys.argv[2] if len(sys.argv) > 2 else ""
        act = sys.argv[3] if len(sys.argv) > 3 else "done"
        cb_id = sys.argv[4] if len(sys.argv) > 4 else None
        res = resolve_takeover(act_id, act, cb_id)
        print(json.dumps(res, ensure_ascii=False, indent=2))
    elif cmd == "resolve_latest":
        act = sys.argv[2] if len(sys.argv) > 2 else "done"
        cb_id = sys.argv[3] if len(sys.argv) > 3 else None
        res = resolve_takeover(None, act, cb_id)
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
