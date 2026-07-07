#!/bin/bash
# ============================================
# sync-upstream.sh
# 从 mihomo-rules 同步域名并生成 dnsmasq 解锁配置
# ============================================
set -euo pipefail

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
  --dry-run             仅输出到 stdout，不写入文件
  --diff                对比现有文件，显示差异 (不写入)
  --check               验证生成配置的域名合法性
  -h, --help            显示此帮助

示例:
  # 默认路径，生成占位符配置
  ./sync-upstream.sh

  # 预览生成内容
  ./sync-upstream.sh --dry-run

  # 对比上次生成的配置
  ./sync-upstream.sh --diff

  # 指定路径和 DNS IP
  ./sync-upstream.sh -d ../mihomo-rules/ruleset -o ./etc/dnsmasq.conf \\
    --dns-ip 10.0.0.1
EOF
  exit 0
}

# --- 解析参数 ---
DNS_IP="<DNS_IP>"
DRY_RUN=false
DIFF_MODE=false
CHECK_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--rules-dir) RULES_DIR="$2"; shift 2 ;;
    -o|--output)    OUTPUT="$2";    shift 2 ;;
    --dns-ip)       DNS_IP="$2";    shift 2 ;;
    --dry-run)      DRY_RUN=true;   shift ;;
    --diff)         DIFF_MODE=true; shift ;;
    --check)        CHECK_MODE=true; shift ;;
    -h|--help)      usage ;;
    *) echo "未知参数: $1"; usage ;;
  esac
done

# --- 检查规则集目录 ---
if [[ ! -d "$RULES_DIR" ]]; then
  echo "错误: 规则集目录不存在: $RULES_DIR" >&2
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
    global)   echo "# >> 全球通用 <<" ;;
    ai)       echo "# >> AI 服务 <<" ;;
    taiwan)   echo "# >> 台湾 <<" ;;
    hongkong) echo "# >> 香港 <<" ;;
    japan)    echo "# >> 日本 <<" ;;
  esac
}

# --- 域名合法性校验 ---
validate_domain() {
  local domain="$1"
  # 只允许: 字母数字 . - _ (部分域名含下划线)
  if [[ ! "$domain" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    return 1
  fi
  return 0
}

# --- 生成配置内容 (输出到 stdout) ---
generate_config() {
  local dns_ip="$1"

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

  local current_region=""
  local has_issues=false

  for entry in "${ALL_PLATFORMS[@]}"; do
    local fname="${entry%%:*}"
    local pname="${entry#*:}"
    local yaml_file="$RULES_DIR/${fname}.yaml"

    if [[ ! -f "$yaml_file" ]]; then
      continue
    fi

    local region="${REGION_MAP[$fname]}"
    if [[ "$region" != "$current_region" ]]; then
      current_region="$region"
      echo ""
      region_header "$region"
      echo ""
    fi

    # 用 awk 提取 DOMAIN 和 DOMAIN-SUFFIX，跳过 regexp
    # BUGFIX: DOMAIN-SUFFIX 可能带前导 + (如 +.example.com)，需 strip
    mapfile -t raw_domains < <(
      awk '
        /^  - DOMAIN,/ {
          if ($0 ~ /DOMAIN,regexp:/) next
          sub(/^  - DOMAIN,/, "")
          gsub(/[ \t]+$/, "")
          if ($0 != "") print $0
        }
        /^  - DOMAIN-SUFFIX,/ {
          if ($0 ~ /DOMAIN-SUFFIX,regexp:/) next
          sub(/^  - DOMAIN-SUFFIX,/, "")
          sub(/^\+/, "")  # 去掉 Loyalsoldier 格式的 + 前缀
          gsub(/[ \t]+$/, "")
          if ($0 != "") print $0
        }
      ' "$yaml_file"
    )

    if [[ ${#raw_domains[@]} -eq 0 ]]; then
      continue
    fi

    # 去重 + 排序 (一行搞定: sort -u)
    local sorted_domains=()
    local tmp_domains=""
    tmp_domains=$(printf "%s\n" "${raw_domains[@]}" | sort -u) || true
    mapfile -t sorted_domains <<< "$tmp_domains"

    # 全局去重过滤
    local unique_domains=()
    for d in "${sorted_domains[@]}"; do
      if [[ -z "${SEEN_DOMAINS[$d]:-}" ]]; then
        SEEN_DOMAINS["$d"]=1
        unique_domains+=("$d")
      fi
    done

    if [[ ${#unique_domains[@]} -eq 0 ]]; then
      continue
    fi

    # 校验模式：检查域名合法性
    if [[ "$CHECK_MODE" == true ]]; then
      local bad_domains=()
      for d in "${unique_domains[@]}"; do
        if ! validate_domain "$d"; then
          bad_domains+=("$d")
        fi
      done
      if [[ ${#bad_domains[@]} -gt 0 ]]; then
        echo "⚠️  [${pname}] 发现 ${#bad_domains[@]} 个可疑域名:" >&2
        for d in "${bad_domains[@]}"; do
          echo "     $d" >&2
        done
        has_issues=true
      fi
    fi

    echo "# >> ${pname} 域名"
    for d in "${unique_domains[@]}"; do
      echo "server=/${d}/${dns_ip}"
    done
    echo ""
  done

  cat <<EOF
# ============================================
# 结束
# ============================================
EOF

  if [[ "$has_issues" == true ]]; then
    echo "⚠️ 校验完成，发现可疑域名，请检查上游规则集" >&2
  fi
}

# --- 统计已匹配的平台数 ---
count_platforms() {
  local count=0
  for entry in "${ALL_PLATFORMS[@]}"; do
    local fname="${entry%%:*}"
    if [[ -f "$RULES_DIR/${fname}.yaml" ]]; then
      ((count++))
    fi
  done
  echo "$count"
}

# ============================================
# 主逻辑
# ============================================

# 校验模式：只检查，不生成
if [[ "$CHECK_MODE" == true ]]; then
  echo "🔍 域名校验模式 — 检查上游规则集中的域名合法性"
  echo ""
  generate_config "$DNS_IP" > /dev/null
  exit 0
fi

# 生成配置内容
generated=$(generate_config "$DNS_IP") || { echo "错误: 配置生成失败" >&2; exit 1; }

# 统计
total_rules=$(echo "$generated" | grep -c '^server=/' || true)
total_lines=$(echo "$generated" | wc -l)
total_platforms=$(count_platforms)

# dry-run 模式：输出到 stdout 即可
if [[ "$DRY_RUN" == true ]]; then
  echo "$generated"
  echo ""
  echo "# --- 统计: ${total_platforms} 平台, ${total_rules} 域名规则, ${total_lines} 行 ---" >&2
  exit 0
fi

# diff 模式：对比现有文件
if [[ "$DIFF_MODE" == true ]]; then
  if [[ -f "$OUTPUT" ]]; then
    if diff -u "$OUTPUT" - <<< "$generated"; then
      echo "✅ 无变化 — 现有配置已是最新"
    fi
  else
    echo "📄 现有文件不存在: $OUTPUT"
    echo "$generated" | head -5
    echo "   ... (${total_rules} 条规则, ${total_lines} 行)"
  fi
  exit 0
fi

# 正常模式：原子写入
output_dir=$(dirname "$OUTPUT")
if [[ ! -d "$output_dir" ]]; then
  mkdir -p "$output_dir"
fi

tmpfile="${OUTPUT}.tmp.$$"
echo "$generated" > "$tmpfile"
mv "$tmpfile" "$OUTPUT"

echo "✅ 配置已生成: $OUTPUT"
echo "   平台数: ${total_platforms}"
echo "   域名规则: ${total_rules}"
echo "   总行数: ${total_lines}"
echo ""

if [[ "$DNS_IP" == "<DNS_IP>" ]]; then
  echo "📌 使用前请将 <DNS_IP> 替换为你的解锁 DNS 地址:"
  echo "   sed -i 's/<DNS_IP>/你的解锁DNS地址/g' $OUTPUT"
fi