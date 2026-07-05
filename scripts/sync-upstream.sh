#!/bin/bash
# ============================================
# sync-upstream.sh
# 从 mihomo-rules 同步域名并生成 dnsmasq 解锁配置
# ============================================
set -uo pipefail

# --- 默认路径 ---
RULES_DIR="${RULES_DIR:-~/mihomo-rules/ruleset}"
OUTPUT="${OUTPUT:-./etc/dnsmasq.conf}"

# --- 帮助 ---
usage() {
  cat <<EOF
用法: $(basename "$0") [选项]

选项:
  -d, --rules-dir DIR   mihomo-rules 规则集目录 (默认: ~/mihomo-rules/ruleset)
  -o, --output FILE     输出文件路径 (默认: ./etc/dnsmasq.conf)
  --dns-ip IP           解锁 DNS IP (默认: <DNS_IP>，留作占位符)
  --skip-verify         跳过输出目录检查
  -h, --help            显示此帮助

示例:
  # 默认路径，生成占位符配置
  ./sync-upstream.sh

  # 指定路径和 DNS IP
  ./sync-upstream.sh -d ../mihomo-rules/ruleset -o ./etc/dnsmasq.conf \\
    --dns-ip 10.0.0.1
EOF
  exit 0
}

# --- 解析参数 ---
DNS_IP="<DNS_IP>"
SKIP_VERIFY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--rules-dir) RULES_DIR="$2"; shift 2 ;;
    -o|--output)    OUTPUT="$2";    shift 2 ;;
    --dns-ip)       DNS_IP="$2";    shift 2 ;;
    --skip-verify)  SKIP_VERIFY=true; shift ;;
    -h|--help)      usage ;;
    *) echo "未知参数: $1"; usage ;;
  esac
done

# --- 检查规则集目录 ---
if [[ ! -d "$RULES_DIR" ]]; then
  echo "错误: 规则集目录不存在: $RULES_DIR"
  exit 1
fi

# --- 平台定义: 文件名:显示名 ---
# 按区域分组

GLOBAL_STREAM=(
  "Netflix:Netflix"
  "Disney:Disney+"
  "PrimeVideo:Prime Video"
  "HBO:HBO Max"
  "DAZN:DAZN"
  "Hotstar:Hotstar"
  "Bilibili:Bilibili"
  "Viu:Viu"
  "TikTok:TikTok"
  "Tubi:Tubi"
  "F1TV:F1 TV"
  "Deezer:Deezer"
  "AppleTV:Apple TV"
)

AI_SERVICES=(
  "OpenAI:OpenAI / ChatGPT"
  "Anthropic:Anthropic / Claude"
  "GoogleAI:Google Gemini"
  "Perplexity:Perplexity"
  "Poe:Poe"
)

TAIWAN=(
  "KKTV:KKTV"
  "LiTV:LiTV"
  "MyVideo:MyVideo"
  "LineTV:Line TV"
  "HamiVideo:Hami Video"
  "CatchPlay:CatchPlay+"
  "Bahamut:Bahamut 动画疯"
  "FridayVideo:Friday 影音"
  "Bangumi:Bangumi"
)

HONGKONG=(
  "NowE:Now E"
  "MyTVSuper:MyTV Super"
  "HOYTV:HOY TV"
)

JAPAN=(
  "Abema:Abema TV"
  "DMMTV:DMM TV"
  "Hulu:Hulu Japan"
  "TVer:TVer"
  "VideoMarket:VideoMarket"
  "UNext:U-Next"
  "WOWOW:WOWOW"
  "Telasa:TELASA"
  "DAnimeStore:Anime Store"
  "FujiTV:富士电视台"
  "RakutenTV:Rakuten TV"
  "Lemino:Lemino"
  "NHK:NHK Plus"
  "Niconico:Niconico"
  "Radiko:radiko"
  "MusicJp:Music Japan"
  "Qobuz:Qobuz"
  "Tidal:Tidal"
  "Mora:mora"
  "Musixmatch:Musixmatch"
  "KaraokeDam:DAM"
  "ReadsJapan:Read Japan"
)

# 合并所有平台
ALL_PLATFORMS=()
declare -A REGION_MAP

for entry in "${GLOBAL_STREAM[@]}"; do
  ALL_PLATFORMS+=("$entry")
  REGION_MAP["${entry%%:*}"]="global"
done
for entry in "${AI_SERVICES[@]}"; do
  ALL_PLATFORMS+=("$entry")
  REGION_MAP["${entry%%:*}"]="ai"
done
for entry in "${TAIWAN[@]}"; do
  ALL_PLATFORMS+=("$entry")
  REGION_MAP["${entry%%:*}"]="taiwan"
done
for entry in "${HONGKONG[@]}"; do
  ALL_PLATFORMS+=("$entry")
  REGION_MAP["${entry%%:*}"]="hongkong"
done
for entry in "${JAPAN[@]}"; do
  ALL_PLATFORMS+=("$entry")
  REGION_MAP["${entry%%:*}"]="japan"
done

# --- 唯一域名追踪 ---
declare -A SEEN_DOMAINS

# --- 区域节点头部 ---
region_header() {
  local region="$1"
  case "$region" in
    global)    echo "# >> 全球通用 <<" ;;
    ai)        echo "# >> AI 服务 <<" ;;
    taiwan)    echo "# >> 台湾 <<" ;;
    hongkong)  echo "# >> 香港 <<" ;;
    japan)     echo "# >> 日本 <<" ;;
  esac
}

# --- 写入文件 ---
{
  cat <<EOF
# ============================================
# dnsmasq.conf – 流媒体 DNS 解锁配置
# 由 sync-upstream.sh 自动生成
# 生成时间: $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S')
# 上游: 从 mihomo-rules 规则集同步
# ============================================

# 禁用读取 /etc/resolv.conf（由下方自定义上游接管）
no-resolv

# 默认上游 DNS（普通流量走国外 DNS，避免国内污染影响解锁判断）
server=1.1.1.1
server=8.8.8.8

# DNS 缓存
cache-size=2048

# 本地 TTL
local-ttl=60

# 监听地址（按需修改）
listen-address=127.0.0.1

# ============================================
# 流媒体 / AI 服务解锁
# 将 <DNS_IP> 替换为你的解锁 DNS 服务器地址
# ============================================
EOF

  current_region=""
  for entry in "${ALL_PLATFORMS[@]}"; do
    fname="${entry%%:*}"
    pname="${entry#*:}"
    yaml_file="$RULES_DIR/${fname}.yaml"

    if [[ ! -f "$yaml_file" ]]; then
      continue
    fi

    region="${REGION_MAP[$fname]}"
    if [[ "$region" != "$current_region" ]]; then
      current_region="$region"
      echo ""
      region_header "$region"
      echo ""
    fi

    # 用 awk 提取 DOMAIN 和 DOMAIN-SUFFIX，跳过 regexp
    mapfile -t domains < <(
      awk -v dns_ip="$DNS_IP" '
        /^  - DOMAIN,/ {
          # 跳过 regexp
          if ($0 ~ /DOMAIN,regexp:/) next
          sub(/^  - DOMAIN,/, "")
          gsub(/[ \t]+$/, "")
          if ($0 != "") print $0
        }
        /^  - DOMAIN-SUFFIX,/ {
          # 跳过 regexp
          if ($0 ~ /DOMAIN-SUFFIX,regexp:/) next
          sub(/^  - DOMAIN-SUFFIX,/, "")
          gsub(/[ \t]+$/, "")
          if ($0 != "") print $0
        }
      ' "$yaml_file"
    )

    if [[ ${#domains[@]} -eq 0 ]]; then
      continue
    fi

    # 去重 + 排序
    declare -a unique_domains=()
    declare -A local_seen=()
    for d in "${domains[@]}"; do
      if [[ -z "${SEEN_DOMAINS[$d]:-}" ]] && [[ -z "${local_seen[$d]:-}" ]]; then
        unique_domains+=("$d")
        local_seen["$d"]=1
        SEEN_DOMAINS["$d"]=1
      fi
    done

    if [[ ${#unique_domains[@]} -eq 0 ]]; then
      continue
    fi

    # 排序
    IFS=$'\n' unique_domains=($(sort <<< "${unique_domains[*]}")); unset IFS

    echo "# >> ${pname} 域名"
    for d in "${unique_domains[@]}"; do
      echo "server=/${d}/${DNS_IP}"
    done
    echo ""
  done

  cat <<EOF
# ============================================
# 结束
# ============================================
EOF

} > "$OUTPUT"

# --- 输出统计 ---
total_lines=$(wc -l < "$OUTPUT")
total_rules=$(grep -c '^server=/' "$OUTPUT" || true)
total_platforms=0
for entry in "${ALL_PLATFORMS[@]}"; do
  fname="${entry%%:*}"
  if [[ -f "$RULES_DIR/${fname}.yaml" ]]; then
    ((total_platforms++))
  fi
done

echo "✅ 配置已生成: $OUTPUT"
echo "   平台数: ${total_platforms}"
echo "   域名规则: ${total_rules}"
echo "   总行数: ${total_lines}"
echo ""
echo "📌 使用前请将 <DNS_IP> 替换为你的解锁 DNS 地址:"
echo "   sed -i 's/<DNS_IP>/你的解锁DNS地址/g' $OUTPUT"