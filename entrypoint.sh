#!/bin/bash
set -e

# 清理可能残留的 X11 锁文件与旧日志（解决容器重启启动失败问题）
rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1 /root/.vnc/*.pid /root/.vnc/*.log

# 创建 VNC 运行时目录
mkdir -p /root/.vnc

# 初始化 DBus Session 会话环境
if command -v dbus-launch >/dev/null 2>&1; then
    eval $(dbus-launch --sh-syntax)
fi

# 初始化密码
VNC_PWD=${VNC_PASSWORD:-"hermes"}
echo -e "$VNC_PWD\n$VNC_PWD" | vncpasswd -u root -w

# 自动初始化 Hermes Agent 配置（OpenRouter + Browser Use + Telegram + Firecrawl）
mkdir -p /root/.hermes
> /root/.hermes/.env
[ -n "$OPENROUTER_API_KEY" ] && echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" >> /root/.hermes/.env
[ -n "$TELEGRAM_BOT_TOKEN" ] && echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" >> /root/.hermes/.env
[ -n "$TELEGRAM_ALLOWED_USERS" ] && echo "TELEGRAM_ALLOWED_USERS=$TELEGRAM_ALLOWED_USERS" >> /root/.hermes/.env
[ -n "$FIRECRAWL_API_KEY" ] && echo "FIRECRAWL_API_KEY=$FIRECRAWL_API_KEY" >> /root/.hermes/.env

cat << EOF > /root/.hermes/config.yaml
provider: openrouter
model:
  default: ${HERMES_MODEL:-z-ai/glm-5.3-flash}
openrouter:
  api_key: ${OPENROUTER_API_KEY}
  model: ${HERMES_MODEL:-z-ai/glm-5.3-flash}
terminal:
  backend: local
browser:
  provider: browser-use
  headless: false
web:
  search_backend: firecrawl
  extract_backend: firecrawl
EOF

if [ -n "$FIRECRAWL_API_KEY" ]; then
    cat << EOF >> /root/.hermes/config.yaml
firecrawl:
  api_key: "${FIRECRAWL_API_KEY}"
EOF
fi

if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    cat << EOF >> /root/.hermes/config.yaml
platforms:
  telegram:
    enabled: true
    token: "${TELEGRAM_BOT_TOKEN}"
EOF
    if [ -n "$TELEGRAM_ALLOWED_USERS" ]; then
        echo "    allow_from:" >> /root/.hermes/config.yaml
        IFS=',' read -ra ADDR <<< "$TELEGRAM_ALLOWED_USERS"
        for i in "${ADDR[@]}"; do
            echo "      - \"${i// /}\"" >> /root/.hermes/config.yaml
        done
    fi
fi

# 确保登录终端自动加载环境变量
grep -q "OPENROUTER_API_KEY" /root/.bashrc 2>/dev/null || cat << 'EOF' >> /root/.bashrc
[ -f /root/.hermes/.env ] && export $(cat /root/.hermes/.env | xargs 2>/dev/null)
[ -n "$HERMES_MODEL" ] && export HERMES_MODEL="$HERMES_MODEL"
[ -n "$FIRECRAWL_API_KEY" ] && export FIRECRAWL_API_KEY="$FIRECRAWL_API_KEY"
EOF

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

# 启动 KasmVNC 服务（DISPLAY :1，端口 8444，指定 xfce 避免进入终端交互菜单）
vncserver :1 -geometry 1440x900 -depth 24 -websocketPort 8444 -interface 0.0.0.0 -select-de xfce

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
