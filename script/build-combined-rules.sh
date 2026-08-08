#!/bin/bash
set -euo pipefail
export PYTHONIOENCODING=utf-8

# 1. 强制切换到当前脚本所在绝对路径
cd "$(cd "$(dirname "$0")"; pwd)"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"; }
warn() { echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $*" >&2; }
error() { echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2; }

# 2. 内存盘临时工作区（优先 /dev/shm，极速且不损耗 SSD 寿命）
WORK_DIR="/dev/shm/mihomo_rules_$$"
if [[ ! -d "/dev/shm" ]]; then
    WORK_DIR="./temp_build_$$"
fi
mkdir -p "$WORK_DIR"

# 全局退出 Trap 清洗机制（无论报错还是被 kill 均能干净收尾）
cleanup() {
    rm -rf "$WORK_DIR" ./*.gz 2>/dev/null || true
    [[ -n "${mihomo_tool:-}" && -f "$mihomo_tool" ]] && rm -f "$mihomo_tool"
}
trap cleanup EXIT INT TERM

# 3. 规则组声明
declare -A RULES=(
    [Ad]="sort-adblock.py
        https://raw.githubusercontent.com/Cats-Team/dns-filter/main/abp.txt
        https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/AWAvenue-Ads-Rule.txt
        https://raw.githubusercontent.com/217heidai/adblockfilters/main/rules/adblockdnslite.txt
        https://gist.githubusercontent.com/qq6510/45173fd5128994bfbe0add665dec8b19/raw/xiaomi.txt
    "
    [AI]="sort-clash.py
        https://raw.githubusercontent.com/QuixoticHeart/rule-set/ruleset/meta/domain/ai.list
        https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/github.list
        https://gist.githubusercontent.com/qq6510/c336dd2875fbf04fb50e1016783592d4/raw/Copilot.list
    "
    [zhi]="sort-clash.py
        https://gist.githubusercontent.com/qq6510/6dbc21f01af78b3a239064d86995fa5f/raw/zh.txt
        https://raw.githubusercontent.com/QuixoticHeart/rule-set/ruleset/meta/domain/fake-ip-filter.list
        https://github.com/QuixoticHeart/rule-set/raw/ruleset/meta/domain/onedrive.list
    "
    [Proxy]="sort-clash.py
        https://raw.githubusercontent.com/QuixoticHeart/rule-set/ruleset/meta/domain/gfw.list
        https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt
    "
)

# 4. 环境检测与 Mihomo 工具部署
setup_mihomo_tool() {
    local tag="v1.19.13"
    local arch
    arch="$(uname -m)"

    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="armv7" ;;
        *) error "不支持的架构: $arch"; exit 1 ;;
    esac

    log "部署 Mihomo 核心工具 (${arch}, ${tag})..."
    local download_url="https://github.com/MetaCubeX/mihomo/releases/download/${tag}/mihomo-linux-${arch}-${tag}.gz"

    if ! wget -q -O mihomo.gz "$download_url"; then
        error "下载 Mihomo 工具失败，请检查网络连接。"
        exit 1
    fi

    gunzip -f mihomo.gz
    chmod +x mihomo
    mihomo_tool="./mihomo"
}

# 5. 组级处理函数
process_rules() {
    local name=$1
    local script=$2
    shift 2
    local urls=("$@")

    local group_dir="$WORK_DIR/$name"
    mkdir -p "$group_dir"

    local domain_file="$group_dir/domain.txt"
    local mihomo_txt_file="$group_dir/${name}_Mihomo.txt"
    local mihomo_mrs_file="$group_dir/${name}_Mihomo.mrs"

    log "[$name] 开始处理组任务..."

    # 5.1 纯 Bash 提取并清洗 URL
    local valid_urls=()
    for url in "${urls[@]}"; do
        url="${url#"${url%%[![:space:]]*}"}"
        url="${url%"${url##*[![:space:]]}"}"
        [[ -n "$url" ]] && valid_urls+=("$url")
    done

    if [[ ${#valid_urls[@]} -eq 0 ]]; then
        warn "[$name] 未包含有效 URL，略过。"
        return 0
    fi

    # 5.2 构建 curl -Z 高并发 HTTP/2 下载指令
    local curl_cmd=(curl --parallel --parallel-immediate --http2 --compressed --max-time 30 --retry 3 -fsSL)
    local idx=1
    for url in "${valid_urls[@]}"; do
        curl_cmd+=("-o" "$group_dir/${idx}.tmp" "$url")
        ((idx++))
    done

    if ! "${curl_cmd[@]}"; then
        warn "[$name] 部分 URL 下载失败或超时，将尽可能拼合有效数据..."
    fi

    # 5.3 内存中拼合文本并清洗 CR 换行符
    > "$domain_file"
    for ((i=1; i<idx; i++)); do
        local tmp_file="$group_dir/${i}.tmp"
        if [[ -s "$tmp_file" ]]; then
            tr -d '\r' < "$tmp_file" >> "$domain_file"
            echo "" >> "$domain_file"
        fi
    done

    # 5.4 校验 Python 脚本并执行去重/清洗
    if [[ ! -f "$script" ]]; then
        error "[$name] 找不到指定的 Python 脚本: $script"
        return 1
    fi

    if ! python3 "$script" "$domain_file"; then
        error "[$name] Python 脚本 $script 执行失败，跳过后续编译步骤。"
        return 1
    fi

    # 5.5 Awk 高性能格式化与修饰 (+.)
    awk '{
        sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "");
        if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[#!]/) next;
        if ($0 !~ /^\+\./) print "+."$0;
        else print $0;
    }' "$domain_file" > "$mihomo_txt_file"

    # 5.6 转换为 mrs 二进制文件
    if ! "$mihomo_tool" convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file"; then
        error "[$name] Mihomo 编译 ruleset 失败"
        return 1
    fi

    # 5.7 归档至工作空间
    mkdir -p ../txt
    mv "$mihomo_txt_file" "../txt/${name}_Mihomo.txt"
    mv "$mihomo_mrs_file" "../${name}_Mihomo.mrs"

    log "[$name] 组处理完成！"
}

# --- 主程序入口 ---

setup_mihomo_tool

log "启动规则全并发处理引擎..."

# 组间并行执行 (& + wait)
for name in "${!RULES[@]}"; do
    mapfile -t lines < <(echo "${RULES[$name]}" | sed '/^[[:space:]]*$/d')

    script="${lines[0]}"
    script="${script#"${script%%[![:space:]]*}"}"
    script="${script%"${script##*[![:space:]]}"}"
    urls=("${lines[@]:1}")

    process_rules "$name" "$script" "${urls[@]}" &
done

wait

log "全部规则组自动化处理完毕！"
