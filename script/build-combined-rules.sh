#!/bin/bash

# 切换到脚本所在目录
cd $(cd "$(dirname "$0")";pwd)

# 定义日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $@"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $@" >&2
}

# 定义规则源
declare -A RULES=(
    [Ad]="sort-adblock.py
        https://raw.githubusercontent.com/qq6510/mij3/main/domains.txt
        https://raw.githubusercontent.com/Cats-Team/dns-filter/main/abp.txt
        https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/AWAvenue-Ads-Rule.txt
        https://raw.githubusercontent.com/217heidai/adblockfilters/main/rules/adblockdnslite.txt
        https://gist.githubusercontent.com/qq6510/45173fd5128994bfbe0add665dec8b19/raw/xiaomi.txt
    "
    [Proxy]="sort-clash.py
        https://raw.githubusercontent.com/DustinWin/ruleset_geodata/refs/heads/mihomo-ruleset/ai.list
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
        https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Proxy/Proxy_Domain_For_Clash.txt
        https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/refs/heads/release/gfw.txt
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

    # 并行下载到独立文件，避免 >> 导致的竞争冲突
    printf "%s\n" "${urls[@]}" | cat -n | xargs -P 16 -I {} sh -c '
        idx=$(echo "{}" | awk "{print \$1}"); 
        url=$(echo "{}" | awk "{print \$2}"); 
        curl --http2 --compressed --max-time 30 --retry 3 -sSL "$url" > "'"$dl_dir"'/${idx}.tmp"
    '

    # 按序合并
    for f in $(ls "$dl_dir/"*.tmp | sort -V); do
        cat "$f" >> "$domain_file"
        echo "" >> "$domain_file" # 强制换行，防止域名粘连
    done
    rm -rf "$dl_dir"

    sed -i 's/\r//' "$domain_file"
    python3 "$script" "$domain_file"
    
    # 核心清理与格式化
    sed -i 's/^[[:space:].+]*//; s/[[:space:].+]*$//' "$domain_file"
    sed -n '/[a-zA-Z0-9]/ { /^#/! s/^/+./p }' "$domain_file" > "$mihomo_txt_file"

    ./"$mihomo_tool" convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file"
    mv "$mihomo_txt_file" "../txt/$mihomo_txt_file"
    mv "$mihomo_mrs_file" "../$mihomo_mrs_file"
}

setup_mihomo_tool() {
    wget -q https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt
    version=$(cat version.txt)
    mihomo_tool="mihomo-linux-amd64-$version"
    wget -q "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/$mihomo_tool.gz"
    gzip -d "$mihomo_tool.gz"
    chmod +x "$mihomo_tool"
}

setup_mihomo_tool
for name in "${!RULES[@]}"; do
    IFS=$'\n' read -r -d '' script urls <<< "${RULES[$name]}"
    urls=($urls)
    process_rules "$name" "$script" "${urls[@]}" &
done
wait
rm -rf ./*.txt "$mihomo_tool" version.txt
log "脚本执行完成"
