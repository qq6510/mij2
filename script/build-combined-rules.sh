#!/bin/bash

# 简化目录切换，并加上失败退出机制
cd "$(dirname "$0")" || exit 1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $@"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $@" >&2
}

declare -A RULES=(
    [Ad]="sort-adblock.py
        https://raw.githubusercontent.com/Cats-Team/dns-filter/main/abp.txt
        https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/AWAvenue-Ads-Rule.txt
        https://raw.githubusercontent.com/217heidai/adblockfilters/main/rules/adblockdnslite.txt
        https://gist.githubusercontent.com/qq6510/45173fd5128994bfbe0add665dec8b19/raw/xiaomi.txt"
    [Proxy]="sort-clash.py
        https://raw.githubusercontent.com/DustinWin/ruleset_geodata/mihomo-ruleset/ai.list
        https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/github.list
        https://gist.githubusercontent.com/qq6510/c336dd2875fbf04fb50e1016783592d4/raw/Copilot.list"
    [zhi]="sort-clash.py
        https://gist.githubusercontent.com/qq6510/6dbc21f01af78b3a239064d86995fa5f/raw/zh.txt
        https://raw.githubusercontent.com/QuixoticHeart/rule-set/ruleset/meta/domain/fake-ip-filter.list
        https://github.com/QuixoticHeart/rule-set/raw/ruleset/meta/domain/onedrive.list"
    [Proxy2]="sort-clash.py
        https://github.com/DustinWin/ruleset_geodata/releases/download/mihomo-ruleset/tld-proxy.list
        https://github.com/DustinWin/ruleset_geodata/releases/download/mihomo-ruleset/proxy.list
        https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt"
)

process_rules() {
    local name=$1
    local script=$2
    shift 2
    local urls=("$@")
    
    local domain_file="${name}_domain.txt"
    local mihomo_txt_file="${name}_Mihomo.txt"
    local mihomo_mrs_file="${name}_Mihomo.mrs"
    local dl_dir="temp_dl_${name}"

    log "开始处理规则: $name"
    mkdir -p "$dl_dir"

    # 【修复 3】：抛弃脆弱的 xargs 嵌套，改用极其稳定的 Bash 原生后台循环
    local idx=1
    for url in "${urls[@]}"; do
        curl --http2 --compressed --max-time 30 --retry 3 -sSL "$url" > "$dl_dir/${idx}.tmp" &
        ((idx++))
    done
    # 等待当前规则组的几个并发下载完成
    wait 

    # 加上 || true 防止 GitHub Actions 的 set -e 在没找到文件时强行斩断脚本
    cat "$dl_dir"/*.tmp > "$domain_file" 2>/dev/null || true
    rm -rf "$dl_dir"

    sed -i 's/\r//g' "$domain_file" || true
    
    # 此时 $script 已经绝对干净了，绝不会再报 exit code 2
    python3 "$script" "$domain_file"
    
    # 【修复 2】：使用兼容全平台 awk 的最基础正则 [ \t.+]+ 替代 [[:space:].+]
    awk '
        /^[ \t]*#/ { next } 
        /[a-zA-Z0-9]/ {
            gsub(/^[ \t.+]+|[ \t.+]+$/, "");
            if ($0 != "" && !seen[$0]++) {
                print "+." $0
            }
        }
    ' "$domain_file" > "$mihomo_txt_file"

    ./mihomo convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file"
    
    mkdir -p ../txt
    mv "$mihomo_txt_file" "../txt/$mihomo_txt_file"
    mv "$mihomo_mrs_file" "../$mihomo_mrs_file"
    
    rm -f "$domain_file"
}

setup_mihomo_tool() {
    local tag="v1.19.13"
    log "正在从官方仓库下载 Mihomo 工具 (版本: ${tag})..."
    
    local download_url="https://github.com/MetaCubeX/mihomo/releases/download/${tag}/mihomo-linux-amd64-${tag}.gz"
    
    wget -q -O mihomo.gz "$download_url" || {
        error "下载失败，请检查网络或目标版本是否存在。"
        exit 1
    }
    
    gunzip -f mihomo.gz || {
        error "解压 mihomo.gz 失败。"
        exit 1
    }
    
    chmod +x mihomo
    
    if ./mihomo -v >/dev/null 2>&1; then
        log "Mihomo 工具准备就绪 (运行测试通过)"
    else
        error "配置失败，解压后的二进制文件无法在当前系统运行。"
        exit 1
    }
}

# --- 主流程 ---

setup_mihomo_tool

for name in "${!RULES[@]}"; do
    # 【修复 1】：在传参前，先像剃刀一样把隐藏的 \r 回车符彻底斩草除根！
    clean_rule="${RULES[$name]//[$'\r']/}"
    
    rule_array=(${clean_rule})
    script="${rule_array[0]}"
    urls=("${rule_array[@]:1}")
    
    process_rules "$name" "$script" "${urls[@]}" &
done

# 等待所有组 (Ad, Proxy 等) 的并发处理全部结束
wait 

rm -f ./mihomo

log "脚本执行完成"
