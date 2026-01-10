# DDNS-Worker

> 利用CF Worker实现的自动更新 DNS记录（并内置TG消息渠道）

满足精神洁癖和Key洁癖需求的迷你DDNS脚本~

## Install

基于原版，我改为了`github actions`部署到`cloudflare worker`的方式，同时将脚本改为一键脚本

## Linux
### 主控
#### 1. Fork 或 Clone 本仓库
将代码保存到你的 GitHub 仓库中。

#### 2. 获取 Cloudflare 凭证
你需要获取以下信息：
1.  **Account ID**: Cloudflare Dashboard 右侧边栏获取。
2.  **Global API Key**: [点击这里获取](https://dash.cloudflare.com/profile/api-tokens) (用于修改 DNS)。
3.  **API Token**: 创建一个用于部署 Worker 的 Token (模板选择 "Edit Cloudflare Workers")。

#### 3. 配置 GitHub Secrets
在仓库的 `Settings` -> `Secrets and variables` -> `Actions` 中添加以下 Secrets：

#### 必填项
| Secret 名称 | 说明 | 获取方式 |
|-------------|------|----------|
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare 账户 ID | Dashboard 概览页面 |
| `CLOUDFLARE_API_TOKEN` | 用于部署 Worker 的 Token | [API Tokens](https://dash.cloudflare.com/profile/api-tokens) |
| `CF_API_EMAIL` | Cloudflare 登录邮箱 | 你的账号邮箱 |
| `CF_API_KEY` | Global API Key | [API Keys](https://dash.cloudflare.com/profile/api-tokens) |
| `API_SECRET` | 客户端通信密钥 | 自定义一个强密码（如 `MySecurePass123`） |

#### 可选项 (Telegram 通知)
如果不设置，通知功能将自动关闭。
| Secret 名称 | 说明 |
|-------------|------|
| `TG_BOT_TOKEN` | Telegram Bot Token (通过 @BotFather 获取) |
| `TG_CHANNEL_ID` | 接收通知的频道或群组 ID (通常以 -100 开头) |
| `DEFAULT_TTL` | DNS 记录的 TTL 值 (默认为 1，即自动) |

#### 4. 部署
提交代码到 `main` 分支，GitHub Actions 将自动运行部署。
> **注意**: 为了安全起见，部署日志中的 Worker URL 已被隐藏。请前往 [Cloudflare Dashboard](https://dash.cloudflare.com/) -> **Workers & Pages** 查看你的 Worker 访问链接。

### 节点端

```
wget --no-check-certificate -O ddns-install.sh https://raw.githubusercontent.com/iP3ter/ddns-worker/main/ddns-install.sh && chmod +x ddns-install.sh
./ddns-install.sh
```
1 选择`1`进行安装。
2 脚本会引导你输入`Worker`地址、密钥、域名 等信息。
3 安装完成后，脚本会自动配置`Crontab`定时任务。

### Windows

- 主控端：请下载PHP端(单点版)运行 / `php ddns.php`
- 当前版本暂不支持节点端运行

### 特点

适用于管理多个服务器的场景下，可以避免创造多个cloudflare api杂乱且不好看，要是没有，建议使用[我的另外一个项目](https://github.com/iP3ter/cloudflare-ddns)

> 具体运行过程?

- 部署DDNS脚本
- 脚本启动后开始尝试获取IP (根据类型选择IPv4或IPv6)
- 获取IP后开始更新DNS记录
- 写入定时任务，按照参数内时间间隔进行获取 (如果没有的话)

## Support

- 目前仅支持 `CloudFlare`
