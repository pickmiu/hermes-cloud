FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV LANG=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh
ENV LC_ALL=zh_CN.UTF-8

# 1. 基础系统工具、中文字体、轻量 XFCE 桌面环境与 KasmVNC Perl 依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    gnupg \
    git \
    sudo \
    locales \
    fonts-wqy-zenhei \
    ca-certificates \
    libssl-dev \
    ssl-cert \
    dbus-x11 \
    xauth \
    x11-xserver-utils \
    xfce4 \
    xfce4-terminal \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    libswitch-perl \
    libyaml-tiny-perl \
    libhash-merge-simple-perl \
    liblist-moreutils-perl \
    libdatetime-perl \
    libdatetime-timezone-perl \
    && rm -rf /var/lib/apt/lists/*

# 生成中文字符集
RUN echo "zh_CN.UTF-8 UTF-8" > /etc/locale.gen && locale-gen

# 2. 安装官方 Google Chrome（采用 Debian 标准 keyrings 路径）
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && sed -i 's|exec -a "$0" "$HERE/chrome" "$@"|exec -a "$0" "$HERE/chrome" "$@" --no-sandbox|g' /opt/google/chrome/google-chrome \
    && mkdir -p /etc/opt/chrome/policies/managed \
    && echo '{"CommandLineFlagSecurityWarningsEnabled": false, "RemoteDebuggingAllowed": true}' > /etc/opt/chrome/policies/managed/managed_policies.json \
    && rm -rf /var/lib/apt/lists/*

# 3. 安装 KasmVNC 及其依赖
RUN ARCH=$(dpkg --print-architecture) && \
    wget -q https://github.com/kasmtech/KasmVNC/releases/download/v1.3.2/kasmvncserver_bookworm_1.3.2_${ARCH}.deb -O /tmp/kasmvnc.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/kasmvnc.deb \
    && rm -rf /tmp/kasmvnc.deb /var/lib/apt/lists/* \
    && adduser root ssl-cert 2>/dev/null || true

# 4. 预创建工作目录与配置目录
RUN mkdir -p /root/workspace /root/.config/google-chrome /root/.vnc

WORKDIR /root

# 5. 构建 Python 隔离虚拟环境并集成安装 Hermes Agent (Nous Research)
RUN python3 -m venv /root/venv \
    && /root/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /root/venv/bin/pip install --no-cache-dir \
       playwright \
       browser-use \
       httpx \
       python-telegram-bot \
    && git clone --depth 1 https://github.com/NousResearch/hermes-agent.git /opt/hermes-agent \
    && /root/venv/bin/pip install --no-cache-dir -e /opt/hermes-agent

ENV PATH="/root/venv/bin:$PATH"

# 拷贝启动脚本
COPY entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh

EXPOSE 8444

ENTRYPOINT ["/root/entrypoint.sh"]
