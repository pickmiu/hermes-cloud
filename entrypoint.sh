#!/bin/bash
set -e

# 清理可能残留的 X11 锁文件与旧日志（解决容器重启启动失败问题）
rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1 /root/.vnc/*.pid /root/.vnc/*.log

# 清理 Chrome 残留的单例锁文件（解决历史退出留下的 SingletonLock 导致的启动失败）
rm -f /root/.config/google-chrome/Singleton* /root/.config/google-chrome/*/Singleton* /tmp/.org.chromium.Chromium.* 2>/dev/null || true

export DISPLAY=:1
export PATH="/root/venv/bin:$PATH"

# 确保 Google Chrome 企业策略就绪（免除所有 CDP 弹窗与命令行警告）
mkdir -p /etc/opt/chrome/policies/managed
echo '{"CommandLineFlagSecurityWarningsEnabled": false, "RemoteDebuggingAllowed": true}' > /etc/opt/chrome/policies/managed/managed_policies.json

# 确保系统级全局 Chrome 包装器就绪（强制附加完整 CDP 调试参数与非默认 user-data-dir，彻底杜绝 root 崩溃与授权弹窗）
cat << 'EOF' > /usr/local/bin/google-chrome
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}
exec /opt/google/chrome/chrome \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --remote-debugging-port=9222 \
  --remote-allow-origins=* \
  --user-data-dir="${CHROME_USER_DATA_DIR:-/root/.config/google-chrome}" \
  --test-type \
  --disable-infobars \
  --no-first-run \
  --no-default-browser-check \
  "$@"
EOF
chmod +x /usr/local/bin/google-chrome
ln -sf /usr/local/bin/google-chrome /usr/bin/google-chrome
ln -sf /usr/local/bin/google-chrome /usr/bin/google-chrome-stable
ln -sf /usr/local/bin/google-chrome /usr/bin/x-www-browser
ln -sf /usr/local/bin/google-chrome /usr/bin/gnome-www-browser

# 配置 XFCE 默认首选浏览器
mkdir -p /root/.config/xfce4 /etc/xdg/xfce4
echo "WebBrowser=google-chrome" > /root/.config/xfce4/helpers.rc
echo "WebBrowser=google-chrome" > /etc/xdg/xfce4/helpers.rc

# 创建 VNC 运行时目录与 Hermes 配置目录
mkdir -p /root/.vnc /root/.hermes /root/.hermes/custom_tools /root/.hermes/skills/request_human_takeover /root/workspace

# 初始化 DBus Session 会话环境
if command -v dbus-launch >/dev/null 2>&1; then
    eval $(dbus-launch --sh-syntax)
fi

# 初始化基础密码文件（KasmVNC 强制要求密码文件存在）
VNC_PWD=${VNC_PASSWORD:-"hermes"}
echo -e "$VNC_PWD\n$VNC_PWD" | vncpasswd -u root -w

# 配置是否禁用 Basic 认证（免密模式）
AUTH_FLAGS=""
if [ "$DISABLE_AUTH" = "true" ] || [ "$VNC_PASSWORD" = "none" ]; then
    AUTH_FLAGS="-disableBasicAuth"
    echo "KasmVNC: Basic Auth disabled (Passwordless direct login enabled)"
fi

# 自动初始化 Hermes Agent 配置（OpenRouter + Browser Use + Telegram + Firecrawl + Takeover Protocol）
> /root/.hermes/.env
echo "DISPLAY=:1" >> /root/.hermes/.env
echo "AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/google-chrome-stable" >> /root/.hermes/.env
echo "AGENT_BROWSER_ARGS=--no-sandbox,--disable-dev-shm-usage,--disable-gpu,--remote-debugging-port=9222,--remote-allow-origins=*,--user-data-dir=/root/.config/google-chrome,--test-type,--disable-infobars,--no-first-run,--no-default-browser-check,--display=:1" >> /root/.hermes/.env
echo "PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome-stable" >> /root/.hermes/.env
echo "CHROME_PATH=/usr/bin/google-chrome-stable" >> /root/.hermes/.env
[ -n "$OPENROUTER_API_KEY" ] && echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" >> /root/.hermes/.env
[ -n "$TELEGRAM_BOT_TOKEN" ] && echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" >> /root/.hermes/.env
[ -n "$TELEGRAM_ALLOWED_USERS" ] && echo "TELEGRAM_ALLOWED_USERS=$TELEGRAM_ALLOWED_USERS" >> /root/.hermes/.env
[ -n "$FIRECRAWL_API_KEY" ] && echo "FIRECRAWL_API_KEY=$FIRECRAWL_API_KEY" >> /root/.hermes/.env
[ -n "$REMOTE_DESKTOP_URL" ] && echo "REMOTE_DESKTOP_URL=$REMOTE_DESKTOP_URL" >> /root/.hermes/.env

cat << EOF > /root/.hermes/config.yaml
provider: openrouter
model: "${HERMES_MODEL:-z-ai/glm-5.3-flash}"
default_model: "${HERMES_MODEL:-z-ai/glm-5.3-flash}"
openrouter:
  api_key: "${OPENROUTER_API_KEY}"
  default_model: "${HERMES_MODEL:-z-ai/glm-5.3-flash}"
terminal:
  backend: local
browser:
  provider: browser-use
  headless: false
  executable_path: /usr/bin/google-chrome-stable
web:
  search_backend: firecrawl
  extract_backend: firecrawl
system_prompt: |
  你是部署在具备完整 X11 桌面与浏览器环境的自主 AI 智能体 Hermes。
  【重要人机协作准则 - 静默极简原则】
  你在操作浏览器执行任务时，遇到需要登录认证（如淘宝/京东/微信扫码登录）、短信验证码、浏览器授权弹窗、或复杂无法绕过的人机验证码时：
  1. 允许自主尝试 1~2 次；
  2. 若无法自主突破或需要人类在屏幕上点击授权/扫码，你必须直接在终端执行：
     python3 /root/takeover_helper.py request "<需要人类协助的具体事项说明>"
  3. 【极简防啰嗦规则】：
     - 严禁在调用前后输出长篇大论的解释、状态复述或重复追问！
     - 调用后只需输出一句极简短语（例如：“登录页已就绪，把电脑交给你，扫码或输账号都行。”），然后立即保持静默，安静等待用户点击 Telegram 按钮。
custom_tools:
  - name: request_human_takeover
    description: "当遇到必须人类介入（如扫码登录、手机短信验证码、浏览器授权弹窗、复杂人机校验）且自主尝试无法解决时调用此工具向用户 Telegram 发送桌面截图与接管按钮卡片。"
    parameters:
      type: object
      properties:
        reason:
          type: string
          description: "需要人类介入的具体原因或操作指引"
      required:
        - reason
    command: "python3 /root/takeover_helper.py request \"{reason}\""
EOF

if [ -n "$FIRECRAWL_API_KEY" ]; then
    cat << EOF >> /root/.hermes/config.yaml
firecrawl:
  api_key: "${FIRECRAWL_API_KEY}"
EOF
fi

if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    HOME_UID="${TELEGRAM_ALLOWED_USERS%%,*}"
    [ -n "$HOME_UID" ] && echo "TELEGRAM_HOME_CHANNEL=$HOME_UID" >> /root/.hermes/.env
    cat << EOF >> /root/.hermes/config.yaml
platforms:
  telegram:
    enabled: true
    token: "${TELEGRAM_BOT_TOKEN}"
EOF
    if [ -n "$HOME_UID" ]; then
        echo "    home_channel: \"$HOME_UID\"" >> /root/.hermes/config.yaml
    fi
    if [ -n "$TELEGRAM_ALLOWED_USERS" ]; then
        echo "    allow_from:" >> /root/.hermes/config.yaml
        IFS=',' read -ra ADDR <<< "$TELEGRAM_ALLOWED_USERS"
        for i in "${ADDR[@]}"; do
            echo "      - \"${i// /}\"" >> /root/.hermes/config.yaml
        done
    fi
fi

# 写入 Hermes 专属 Skill 技能文档（agentskills.io 标准）
cat << 'EOF' > /root/.hermes/skills/request_human_takeover/SKILL.md
---
name: request_human_takeover
description: 当遇到扫码登录（淘宝、支付宝、微信等）、短信验证码、手机授权、浏览器弹窗授权、复杂人机验证码且自主尝试 1~2 次无法突破时，必须使用此技能向人类发送桌面截图和 Telegram 交互接管卡片。
metadata:
  version: 1.0.0
---

# Human Takeover Protocol (极简人机接管技能)

## 触发条件
当操作浏览器或执行任务遇到以下情况且自主尝试 1~2 次仍无法解决时：
1. **扫码登录**：淘宝、京东、微信、支付宝等网页弹出登录二维码。
2. **验证码阻拦**：复杂拼图、滑块、旋转验证码、短信验证码发到用户手机。
3. **授权弹窗**：浏览器提示需要用户点击授权、或者页面弹出阻塞性弹窗。
4. **敏感操作**：支付密码、删除核心配置等。

## 执行指令
立即在终端中执行以下命令（将具体原因作为参数传入）：

```bash
python3 /root/takeover_helper.py request "<需要人类协助的具体事项说明>"
```

### 示例
遇到淘宝登录时运行：
```bash
python3 /root/takeover_helper.py request "Log in to Taobao (scan QR or account + password)"
```

## 执行后动作（严格遵守静默原则）
执行上述命令后：
1. 系统已自动向用户 Telegram 发送了带截图的交互卡片。
2. **严禁多余废话**：输出一句话（例如：“登录页还在。把电脑交给你，扫码或输账号都行。”），然后**立即停止输出，保持完全静默**！
3. **严禁在调用后重复复述卡片内容、严禁发长文、严禁重复追问**。
4. 收到通知后，重新获取最新页面状态并继续执行原任务。
EOF

# 写入工作区全局行为规范 (AGENTS.md)
cat << 'EOF' > /root/workspace/AGENTS.md
# Hermes Workspace Behavioral Rules

## 核心准则：自主优先与极简人机接管 (Autonomous-First & Silent Human Takeover)

1. **自主尝试**：遇到常规表单登录或常规验证码，先自主尝试 1~2 次。
2. **触发接管**：若遇到手机扫码（淘宝/微信/支付宝等）、短信验证码、浏览器授权弹窗、支付或无法通过的验证码，立即在终端运行：
   `python3 /root/takeover_helper.py request "<说明原因>"`
3. **静默防啰嗦**：执行后仅说一句话（如“登录页已就绪，交给你了”），严禁发长文解释，安静等待用户点击按钮。
EOF
cp /root/workspace/AGENTS.md /root/AGENTS.md 2>/dev/null || true

# 写入 Hermes 专属人机协同与自主尝试协议 (SOUL.md)
cat << 'EOF' > /root/.hermes/SOUL.md
# Hermes Agent 核心行为与极简人机接管协议 (Autonomous-First & Silent Takeover)

你在操作浏览器（Browser Use）、终端或执行各类任务时，必须严格遵守以下准则：

## 1. 自主优先尝试原则 (Autonomous Attempt)
- 当遇到常规登录框、输入校验或常规图形/滑块验证码等阻碍时，**优先自主尝试 1 ~ 2 次**（利用已有登录凭据、Cookie 或程序化分析）。
- 如果自主尝试成功并进入目标页面，直接继续执行任务，**无需打扰用户**。

## 2. 触发人类接管的条件 (Human Takeover Conditions)
只有在判定为「无法自主完成」时，才允许调用 `request_human_takeover` 技能：
- **物理与设备阻隔**：必须手机 App 扫码（微信/支付宝/淘宝等二维码）、短信验证码发至用户手机、或需要支付密码与生物认证。
- **授权弹窗与阻碍**：浏览器需要人工点击允许授权、弹窗确认等。
- **自主尝试失败**：验证码识别失败或重试 1~2 次仍未通过，继续尝试可能导致封号或锁定时。
- **环境被拦截**：遇到高强度无法绕过的人机验证盾（如 Cloudflare Turnstile）。

## 3. 接管调用规范（极简静默交互）
- 在终端运行 `python3 /root/takeover_helper.py request "Log in to Taobao (scan QR or account + password)"`。
- 系统会自动截取当前桌面画面，并向 Telegram 发送带 [Take over]、[I'm done]、[Skip] 按钮的 Grok 风格卡片。
- **严禁输出多余的前置或后置废话**，调用后仅输出一句极短的话（如：“登录页还在。把电脑交给你，扫码或输账号都行。”），然后立即保持静默。
- 收到人类完成接管的通知后，重新抓取最新页面/屏幕状态，核验后继续完成原定任务。
EOF

# 写入 Python 原生 Custom Tool 包装（确保多模式加载）
cat << 'EOF' > /root/.hermes/custom_tools/takeover_tool.py
import sys
import os
if "/root" not in sys.path:
    sys.path.insert(0, "/root")
import takeover_helper

def request_human_takeover(reason: str) -> str:
    """
    当操作浏览器或执行任务遇到障碍且自主尝试无法突破时（如必须扫码登录、手机验证码、复杂人机验证），
    调用此工具向用户的 Telegram 发送当前桌面最新截图与交互式接管卡片。
    """
    res = takeover_helper.request_human_takeover(reason)
    return str(res)
EOF

# 确保登录终端自动加载环境变量
grep -q "OPENROUTER_API_KEY" /root/.bashrc 2>/dev/null || cat << 'EOF' >> /root/.bashrc
export DISPLAY=:1
export PATH="/root/venv/bin:$PATH"
[ -f /root/.hermes/.env ] && export $(cat /root/.hermes/.env | xargs 2>/dev/null)
[ -n "$HERMES_MODEL" ] && export HERMES_MODEL="$HERMES_MODEL"
[ -n "$FIRECRAWL_API_KEY" ] && export FIRECRAWL_API_KEY="$FIRECRAWL_API_KEY"
[ -n "$REMOTE_DESKTOP_URL" ] && export REMOTE_DESKTOP_URL="$REMOTE_DESKTOP_URL"
EOF

# 自动为 Hermes Telegram Gateway 注入 Takeover Callback 拦截器
if [ -f "/opt/hermes-agent/gateway/platforms/telegram.py" ]; then
    python3 - << 'PYEOF'
import re

path = "/opt/hermes-agent/gateway/platforms/telegram.py"
try:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    # 注入 takeover callback 拦截逻辑
    if "takeover:" not in content:
        hook_code = """
        # --- Hermes Cloud Takeover Callback Hook ---
        if update.callback_query and update.callback_query.data and update.callback_query.data.startswith("takeover:"):
            cb_data = update.callback_query.data
            parts = cb_data.split(":")
            action = parts[1] if len(parts) > 1 else "done"
            act_id = parts[2] if len(parts) > 2 else ""
            import subprocess
            subprocess.run([
                "python3", "/root/takeover_helper.py", "resolve",
                act_id, action, str(update.callback_query.id)
            ], check=False)
            
            # 向会话注入恢复消息
            if action == "done":
                prompt_text = "[系统提示] 用户已在 Telegram 上点击【我已完成接管】，请重新获取当前页面状态并继续执行剩余任务。"
            else:
                prompt_text = "[系统提示] 用户已在 Telegram 上点击【跳过接管】，请跳过当前操作并继续。"
            
            # 通过原生事件分发恢复执行
            if hasattr(self, "_dispatch_user_message"):
                await self._dispatch_user_message(update, prompt_text)
            return
        # --- End Takeover Hook ---
"""
        # 寻找 _handle_callback_query 或 callback handler 入口
        if "async def _handle_callback_query" in content:
            content = content.replace(
                "async def _handle_callback_query(self, update, context):",
                "async def _handle_callback_query(self, update, context):\n" + hook_code
            )
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print("Successfully patched Hermes Telegram Gateway callback handler.")
except Exception as e:
    print(f"Notice: Telegram Gateway patch step: {e}")
PYEOF
fi

# 配置 X11 启动会话（启动 XFCE 桌面）
cat << 'EOF' > /root/.vnc/xstartup
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
[ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources
exec startxfce4
EOF
chmod +x /root/.vnc/xstartup

# 启动 KasmVNC 服务（DISPLAY :1，端口 8444，指定 xfce 避免进入终端交互菜单，按需支持免密）
vncserver :1 -geometry 1440x900 -depth 24 -websocketPort 8444 -interface 0.0.0.0 -select-de xfce $AUTH_FLAGS

# 若配置了 Telegram Token，自动在后台启动 Hermes Telegram 网关
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    echo "Starting Hermes Telegram Gateway service in background..."
    nohup hermes gateway run > /root/.hermes/gateway.log 2>&1 &
fi

# 等待日志文件生成，避免 tail -f 在文件不存在时引发 set -e 容器退出
LOG_FILE=""
for i in {1..10}; do
    LOG_FILE=$(ls /root/.vnc/*:1.log 2>/dev/null | head -n 1)
    if [ -n "$LOG_FILE" ]; then
        break
    fi
    sleep 1
done

if [ -n "$LOG_FILE" ]; then
    exec tail -f "$LOG_FILE"
else
    echo "Warning: VNC log file not found, keeping container active..."
    exec tail -f /dev/null
fi
