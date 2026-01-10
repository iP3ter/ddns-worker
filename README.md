# DDNS-Worker

> 利用 Cloudflare Worker 实现的自动更新 DNS 记录（并内置 TG 消息推送）

满足精神洁癖和 Key 洁癖需求的迷你 DDNS 脚本~

## Install

基于原版，改为使用 `GitHub Actions` 自动部署到 `Cloudflare Worker`，同时提供了客户端一键安装脚本，并且加入了依赖校验这一功能。

## 🐧 Linux

### ☁️ 主控端 (Cloudflare Worker)

#### 1. Fork 本仓库
将代码 Fork 到你的 GitHub 仓库中。

#### 2. 获取 Cloudflare 凭证
你需要获取以下 3 项信息：

1.  **Account ID**: 在 Cloudflare Dashboard 右侧边栏获取。
2.  **Deploy Token (用于部署)**:
    *   [创建 Token](https://dash.cloudflare.com/profile/api-tokens) -> 使用模板 **"Edit Cloudflare Workers"** -> 生成并复制。
3.  **DNS Token (用于修改解析)**:
    *   [创建 Token](https://dash.cloudflare.com/profile/api-tokens) -> 使用模板 **"Edit Zone DNS"**。
    *   **权限**: 确保包含 `Zone - DNS - Edit` 和 `Zone - Zone - Read`。
    *   **资源**: 选择 `All zones` 或指定你的域名。

#### 3. 配置 GitHub Secrets
在仓库的 `Settings` -> `Secrets and variables` -> `Actions` 中添加以下 Secrets：

**✅ 必填项**

| Secret 名称 | 说明 | 获取方式 |
|-------------|------|----------|
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare 账户 ID | Dashboard 概览页面 |
| `CLOUDFLARE_API_TOKEN` | **部署用 Token** | 上一步生成的 "Edit Cloudflare Workers" Token |
| `CF_DNS_API_TOKEN` | **DNS 修改用 Token** | 上一步生成的 "Edit Zone DNS" Token |
| `API_SECRET` | 客户端通信密钥 | 自定义一个强密码（如 `MySecurePass123`） |

**🔔 可选项 (Telegram 通知)**
如果不设置，通知功能将自动关闭。

| Secret 名称 | 说明 |
|-------------|------|
| `TG_BOT_TOKEN` | Telegram Bot Token (通过 @BotFather 获取) |
| `TG_CHANNEL_ID` | 接收通知的频道或群组 ID (通常以 -100 开头) |
| `DEFAULT_TTL` | DNS 记录的 TTL 值 (默认为 1，即自动) |

#### 4. 部署
```
Actions → Deploy DDNS Worker → Run workflow → Run workflow
```
GitHub Actions 将自动运行部署。
> **注意**: 为了防止泄露，部署日志中的 Worker URL 已被隐藏。请前往 [Cloudflare Dashboard](https://dash.cloudflare.com/) -> **Workers & Pages** 查看你的 Worker 访问链接。
为了方便你可以在cloudflare worker绑定一个自己的域名
问：我把 https://cf-ddns-worker.example.workers.dev 绑定到了 yourname.example.com 为啥就不行了
答：当使用自定义域名时，请求会经过该域名的防火墙规则。

方法一：关闭 Bot Fight Mode
```
Cloudflare Dashboard
  → 选择域名
  → Security
  → Bots
  → Bot Fight Mode → 关闭
```
方法二：添加 WAF 白名单规则
```
Cloudflare Dashboard
  → 选择域名
  → Security
  → WAF
  → Custom rules
  → Create rule
```
规则配置：

- Rule name: Allow DDNS
- Expression: (http.host eq "ddns.your-domain.com")
- Action: Skip
- 勾选: All remaining custom rules、Super Bot Fight Mode


### 🖥️ 节点端 (客户端)
在你的服务器上运行以下命令：（兼容 Alpine / Debian / Ubuntu / CentOS）
```bash
wget --no-check-certificate -O ddns-install.sh https://raw.githubusercontent.com/iP3ter/ddns-worker/main/ddns-install.sh && chmod +x ddns-install.sh
./ddns-install.sh
```

1. 选择 1 进行安装。（已经加入了依赖校验，在运行时会自动检测是否有相关依赖）
2. 脚本会引导你输入 Worker 地址、密钥、域名等信息。
3. 安装完成后，脚本会自动配置 Crontab 定时任务。
## 🪟 Windows
主控端：请下载 PHP 端 (单点版) 运行 / php ddns.php
节点端：当前版本暂不支持 Windows 节点端运行 (也许可以使用 WSL)

## ✨ 特点
适用于管理多个服务器的场景下，可以避免创造多个 Cloudflare API Token 导致管理混乱。
要是没有多个服务器的管理需求，建议使用[我的另外一个项目](https://github.com/iP3ter/cloudflare-ddns)

## 运行流程：
1. 部署 Worker 主控端。
2. 客户端脚本启动，获取本机公网 IP (支持 IPv4/IPv6)。
3. 客户端将 IP 发送给 Worker。
4. Worker 验证密钥，并通过 CF API 更新 DNS 记录。
5. (可选) Worker 推送更新通知到 Telegram。
6. 客户端写入定时任务，按设定频率自动检测。
 
## Support
目前仅支持 Cloudflare
