#!/bin/bash

cd $(cd "$(dirname "$0")";pwd)

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
        https://gist.githubusercontent.com/qq6510/45173fd5128994bfbe0add665dec8b19/raw/xiaomi.txt
    "
    [Proxy]="sort-clash.py
        https://raw.githubusercontent.com/DustinWin/ruleset_geodata/mihomo-ruleset/ai.list
        https://gist.githubusercontent.com/qq6510/c336dd2875fbf04fb50e1016783592d4/raw/Copilot.list
    "
    [zhi]="sort-clash.py
        https://gist.githubusercontent.com/qq6510/6dbc21f01af78b3a239064d86995fa5f/raw/zh.txt
        https://raw.githubusercontent.com/QuixoticHeart/rule-set/ruleset/meta/domain/fake-ip-filter.list
        https://github.com/QuixoticHeart/rule-set/raw/ruleset/meta/domain/onedrive.list
    "
    [Proxy2]="sort-clash.py
        https://github.com/DustinWin/ruleset_geodata/releases/download/mihomo-ruleset/tld-proxy.list
        https://github.com/DustinWin/ruleset_geodata/releases/download/mihomo-ruleset/proxy.list
        https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt
    "
)

process_rules() {
    local name=$1
    local script=$2
    shift 2
    local urls=("$@")
    local domain_file="${name}_domain.txt"
    local mihomo_txt_file="${name}_Mihomo.txt"
    local mihomo_mrs_file="${mihomo_txt_file%.txt}.mrs"
    local dl_dir="temp_dl_${name}"

    log "开始处理规则: $name"
    > "$domain_file"
    mkdir -p "$dl_dir"

    printf "%s\n" "${urls[@]}" | cat -n | xargs -P 16 -I {} sh -c '
        idx=$(echo "{}" | awk "{print \$1}"); 
        url=$(echo "{}" | awk "{print \$2}"); 
        curl --http2 --compressed --max-time 30 --retry 3 -sSL "$url" > "'"$dl_dir"'/${idx}.tmp"
    '

    for f in $(ls "$dl_dir/"*.tmp | sort -V); do
        cat "$f" >> "$domain_file"
        echo "" >> "$domain_file"
    done
    rm -rf "$dl_dir"

    sed -i 's/\r//' "$domain_file"
    python3 "$script" "$domain_file"
    
    sed -i 's/^[[:space:].+]*//; s/[[:space:].+]*$//' "$domain_file"
    sed -n '/[a-zA-Z0-9]/ { /^#/! s/^/+./p }' "$domain_file" > "$mihomo_txt_file"

    awk '!seen[$0]++' "$mihomo_txt_file" > "$mihomo_txt_file.tmp" && mv "$mihomo_txt_file.tmp" "$mihomo_txt_file"

    ./"$mihomo_tool" convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file"
    
    mkdir -p ../txt
    mv "$mihomo_txt_file" "../txt/$mihomo_txt_file"
    mv "$mihomo_mrs_file" "../$mihomo_mrs_file"
}

setup_mihomo_tool() {
    log "正在从官方仓库下载 Mihomo 工具 (版本: v1.19.11)..."
    
    local tag="v1.19.11"
    local download_url="https://github.com/MetaCubeX/mihomo/releases/download/${tag}/mihomo-linux-amd64-${tag}.gz"
    
    curl -L "$download_url" -o mihomo.gz
    
    if [ -f "mihomo.gz" ]; then
        gunzip -f mihomo.gz
    else
        error "下载失败，未找到 mihomo.gz"
        exit 1
    fi
    
    if [ -f "mihomo-linux-amd64-${tag}" ]; then
        mv -f "mihomo-linux-amd64-${tag}" mihomo
    fi
    
    if [ -f "mihomo" ]; then
        chmod +x mihomo
        mihomo_tool="mihomo"
        log "Mihomo 工具准备就绪 (版本: MetaCubeX/mihomo $tag)"
    else
        error "解压失败，未找到 mihomo 二进制文件"
        exit 1
    fi
}

setup_mihomo_tool

for name in "${!RULES[@]}"; do
    IFS=$'\n' read -r -d '' script urls <<< "${RULES[$name]}"
    urls=($urls)
    process_rules "$name" "$script" "${urls[@]}" &
done
wait

rm -rf ./*.txt 
rm -f "$mihomo_tool"

log "脚本执行完成"
