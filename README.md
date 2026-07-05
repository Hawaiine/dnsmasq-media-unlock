# 📡 dnsmasq-media-unlock

> 🚀 基于 dnsmasq 的流媒体 DNS 解锁配置，自动从上游规则集同步域名列表，保持最新最全。

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## 🌟 特性一览

| 特性 | 说明 |
|------|------|
| ✅ **自动同步** | 脚本从上游 mihomo-rules 规则集提取域名，一行命令生成配置 |
| 🎯 **覆盖全面** | 52 个平台、689 条域名规则，涵盖全球流媒体 + AI 服务 |
| 🗂️ **按区归类** | 🌐全球通用 / 🤖AI 服务 / 🇹🇼台湾 / 🇭🇰香港 / 🇯🇵日本，一目了然 |
| 🧹 **无重复** | 自动去重，同域名只生成一条规则，配置干净整洁 |
| 📦 **占位符设计** | 所有 `server=` 使用 `<DNS_IP>` 占位符，一行替换即用 |
| 🔄 **可复现** | 上游更新后重新运行脚本即可同步最新域名 |
| 🚫 **无 regexp** | 自动跳过 dnsmasq 不支持的 regexp 条目 |
| 🔒 **resolv.conf 锁** | 支持 `chattr +i` 锁定，防止系统覆盖 |

## 📋 平台覆盖

| 区域 | 平台 |
|------|------|
| 🌐 **全球通用** 🌍 | Netflix、Disney+、Prime Video、HBO Max、DAZN、Hotstar、Bilibili、Viu、TikTok、Tubi、F1 TV、Deezer、Apple TV |
| 🤖 **AI 服务** 🧠 | OpenAI / ChatGPT、Anthropic / Claude、Google Gemini、Perplexity、Poe |
| 🇹🇼 **台湾** 🏝️ | KKTV、LiTV、MyVideo、Line TV、Hami Video、CatchPlay+、Bahamut 动画疯、Friday 影音、Bangumi |
| 🇭🇰 **香港** 🏙️ | Now E、MyTV Super、HOY TV |
| 🇯🇵 **日本** 🗾 | Abema TV、DMM TV、Hulu Japan、TVer、VideoMarket、U-Next、WOWOW、TELASA、Anime Store、富士电视台、Rakuten TV、Lemino、NHK Plus、Niconico、radiko、Music Japan、Qobuz、Tidal、mora、Musixmatch、DAM |

## 🚀 快速开始

### 1️⃣ 生成配置

```bash
# 指定上游规则集目录，生成占位符配置
./scripts/sync-upstream.sh --rules-dir /path/to/mihomo-rules/ruleset
```

### 2️⃣ ✏️ 替换解锁 DNS

将 `<DNS_IP>` 替换为你的解锁 DNS 服务器地址：

```bash
sed -i 's/<DNS_IP>/10.0.0.1/g' etc/dnsmasq.conf
```

### 3️⃣ 📥 部署到 dnsmasq

```bash
# 将配置复制到 dnsmasq 配置目录
cp etc/dnsmasq.conf /etc/dnsmasq.d/99-media-unlock.conf

# 重启 dnsmasq
systemctl restart dnsmasq
```

### 4️⃣ 🔒 锁定 resolv.conf（防还原）

系统 DHCP 或 NetworkManager 可能自动还原 `/etc/resolv.conf`，使用 `chattr` 锁定：

```bash
# 先写入 dnsmasq 地址
echo 'nameserver 127.0.0.1' | tee /etc/resolv.conf

# 锁定文件，防止被覆盖
chattr +i /etc/resolv.conf

# 查看锁定状态
lsattr /etc/resolv.conf
# 输出: ----i--------- /etc/resolv.conf  ← i 表示已锁定
```

> 💡 **如需解锁：** `chattr -i /etc/resolv.conf`

## 🔧 脚本用法

```bash
./scripts/sync-upstream.sh [选项]

选项:
  -d, --rules-dir DIR   mihomo-rules 规则集目录（默认: ~/mihomo-rules/ruleset）
  -o, --output FILE     输出文件路径（默认: ./etc/dnsmasq.conf）
  --dns-ip IP           解锁 DNS IP（默认: <DNS_IP>，留作占位符）
  -h, --help            显示帮助

示例:
  # 默认路径，生成占位符配置
  ./sync-upstream.sh

  # 指定路径和 DNS IP，一键生成可用配置
  ./sync-upstream.sh -d ../mihomo-rules/ruleset --dns-ip 10.0.0.1
```

## ⚙️ 工作原理

```
📂 mihomo-rules/ruleset/*.yaml
          │
          ▼  🔍 提取 DOMAIN 和 DOMAIN-SUFFIX，跳过 regexp 条目
📋 域名列表（按平台分组）
          │
          ▼  🧹 去重 + 📊 按字母排序 + 🗂️ 按区域分组
📝 server=/domain/<DNS_IP>
          │
          ▼  💾 写入文件
📄 etc/dnsmasq.conf
```

## 📦 文件结构

```
dnsmasq-media-unlock/
├── 📁 etc/
│   ├── 📄 dnsmasq.conf      ← 自动生成的解锁配置
│   └── 📄 resolv.conf       ← 系统 DNS 设置（nameserver 127.0.0.1）
├── 📁 scripts/
│   └── 🛠️ sync-upstream.sh  ← 同步脚本（核心！）
└── 📖 README.md             ← 本文件
```

## 🔄 定期更新（Crontab）

将脚本加入 crontab 可定期同步上游更新：

```bash
# 每天凌晨 3 点同步一次
0 3 * * * cd /path/to/dnsmasq-media-unlock && \
  ./scripts/sync-upstream.sh --rules-dir /path/to/mihomo-rules/ruleset && \
  cp etc/dnsmasq.conf /etc/dnsmasq.d/99-media-unlock.conf && \
  systemctl restart dnsmasq
```

## ❓ 常见问题

### 🔍 dnsmasq 是什么？

> dnsmasq 是一个轻量级 DNS 转发器。配合 `server=/domain/dns` 语法，可以将特定域名的 DNS 查询转发到指定 DNS 服务器，实现分流解锁。

### 🧐 resolv.conf 为什么要设为 127.0.0.1？

> 让系统所有 DNS 请求先经过 dnsmasq，由 dnsmasq 判断：
> - 🎬 **匹配解锁规则** → 走解锁 DNS
> - 🌐 **其他流量** → 走普通 DNS（默认 1.1.1.1 / 8.8.8.8，保持国外解析）
>
> 标准的 split-DNS 方案。锁定方法见上方第 4️⃣ 步。

### 🤔 为什么上游 DNS 不用国内的？

> 解锁链路要求**非解锁域名也走国外解析**。如果用国内 DNS（如 223.5.5.5）：
> - 🔒 可能被 DNS 污染，返回错误 IP
> - 🐢 国内 CDN 调度与国外不同，影响解锁判断
>
> 所以默认上游保持 1.1.1.1 / 8.8.8.8 不变。

### ❓ 为什么用 `<DNS_IP>` 占位符？

> 因为每个人的解锁 DNS 地址不同。用占位符生成，你只需 `sed` 替换一次，不必手动编辑几百行配置。

### 🛡️ resolv.conf 总被覆盖怎么办？

> DHCP 或 NetworkManager 会在重启/重连时还原 `/etc/resolv.conf`。使用 `chattr +i` 锁定即可（详见上方第 4️⃣ 步）。

## 📄 许可

MIT