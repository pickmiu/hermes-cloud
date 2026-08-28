# Hermes Desktop (Debian 12 Bookworm + KasmVNC + XFCE4)

基于 Debian 12 (Bookworm) 的轻量级 X11 / KasmVNC 桌面环境容器，支持 Playwright 自动化测试、Python 隔离虚拟环境（PEP 668）以及中文语言支持。

已全面改造为 **Root 单用户运行** 与 **多实例无缝扩展架构**，彻底避免宿主机挂载卷的权限冲突。

---

## 目录结构

```
.
├── Dockerfile              # Debian 12 基础镜像与环境构建文件
├── entrypoint.sh           # 容器启动脚本（处理 DBus、VNC、XFCE 与日志）
├── docker-compose.yml      # Docker Compose 服务定义文件（支持单/多实例）
├── .env.example            # 环境变量配置模板
├── .env                    # 实例端口与密码配置
├── .gitignore              # Git 忽略文件（已忽略运行时数据与敏感配置）
└── README.md               # 项目使用说明文档
```

---

## 快速开始

### 1. 启动默认单实例（实例 1）

默认仅启动 `hermes-desktop-1`：

```bash
docker compose up -d --build
```

* **Web 访问地址**：`https://<你的IP>:8444`
* **用户名**：`root`
* **默认密码**：`hermes` （可在 `.env` 中修改 `VNC_PASSWORD_1`）
* **数据目录**：
  * `./data/instance-1/workspace` -> `/root/workspace`
  * `./data/instance-1/chrome-data` -> `/root/.config/google-chrome`

---

## 多实例管理与扩展

本项目已配置独立的端口、数据卷及 Compose Profile，支持同时运行多个完全隔离的桌面实例。

### 1. 启动全部实例（实例 1 + 实例 2）

```bash
docker compose --profile multi up -d
```

| 实例名称 | Web 访问端口 | 容器名称 | 独立数据目录 |
| :--- | :--- | :--- | :--- |
| **实例 1** | `https://<IP>:8444` | `hermes-desktop-1` | `./data/instance-1/` |
| **实例 2** | `https://<IP>:8445` | `hermes-desktop-2` | `./data/instance-2/` |

### 2. 单独启动或停止指定实例

* 启动指定实例：
  ```bash
  docker compose up -d hermes-desktop-2
  ```
* 停止指定实例：
  ```bash
  docker compose stop hermes-desktop-2
  ```

### 3. 如何新增第 3 个实例？

如需扩展 `hermes-desktop-3`，只需在 [docker-compose.yml](file:///Users/pickmiu/Project/hermes-cloud/docker-compose.yml) 中追加：

```yaml
  hermes-desktop-3:
    <<: *hermes-base
    container_name: hermes-desktop-3
    profiles: ["multi", "all"]
    ports:
      - "8446:8444"
    environment:
      - VNC_PASSWORD=${VNC_PASSWORD_3:-hermes}
    volumes:
      - ./data/instance-3/workspace:/root/workspace
      - ./data/instance-3/chrome-data:/root/.config/google-chrome
```

---

## 命令行交互与测试

### 1. 进入指定容器终端

进入实例 1：
```bash
docker compose exec -it hermes-desktop-1 bash
```

进入实例 2：
```bash
docker compose exec -it hermes-desktop-2 bash
```

### 2. 使用 Hermes Agent 与 Telegram 机器人

容器内已预设 **OpenRouter (`z-ai/glm-5.3-flash`)**、**`Browser Use` 浏览器引擎**、**Firecrawl Web 搜索与内容抓取** 与 **Telegram Bot 7x24h 远程网关**。

#### 配置方式（推荐通过 `.env`）：
在宿主机项目根目录的 `.env` 中填入：
```bash
# 模型配置
OPENROUTER_API_KEY=sk-or-v1-xxxxxxxxxxxxxxxxxxxx
HERMES_MODEL=z-ai/glm-5.3-flash

# Web 搜索与内容抓取 (Firecrawl)
FIRECRAWL_API_KEY=fc-xxxxxxxxxxxxxxxxxxxx

# Telegram 机器人配置
TELEGRAM_BOT_TOKEN=1234567890:ABCdefGhIJKlmNoPQRsTUVwxyZ
TELEGRAM_ALLOWED_USERS=123456789
```
> **自动后台运行**：只要在 `.env` 中配置了 `TELEGRAM_BOT_TOKEN`，容器启动时会自动在后台拉起 `hermes gateway run`。您无需登录服务器，直接在手机 Telegram 上向您的机器人发送指令，Hermes 即可自动执行网页操作并回复结果！

#### 命令行交互：
* **进入容器终端直接与 Agent 对话**：
  ```bash
  docker compose exec -it hermes-desktop-1 bash
  hermes
  ```
* **查看 Telegram 机器人网关日志**：
  ```bash
  docker compose exec -it hermes-desktop-1 cat /root/.hermes/gateway.log
  ```
* **手动管理网关**：
  ```bash
  hermes gateway status
  hermes gateway restart
  ```

### 3. 验证 Playwright 自动化测试

在容器内直接运行 Python 自动化脚本（虚拟环境已自动加载到 `PATH`）：

```bash
python -c '
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    b = p.chromium.launch(
        executable_path="/usr/bin/google-chrome-stable",
        headless=False,
        args=["--no-sandbox"]
    )
    page = b.new_page()
    page.goto("https://www.google.com")
    print("Page title:", page.title())
    import time; time.sleep(10)
'
```

---

## 维护与日志查看

* 查看所有实例日志：
  ```bash
  docker compose logs -f
  ```
* 查看特定实例日志：
  ```bash
  docker compose logs -f hermes-desktop-1
  ```
