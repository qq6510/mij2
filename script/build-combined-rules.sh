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

# 定义规则源 (保持不变)
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

    # 并行下载到独立文件
    printf "%s\n" "${urls[@]}" | cat -n | xargs -P 16 -I {} sh -c '
        idx=$(echo "{}" | awk "{print \$1}"); 
        url=$(echo "{}" | awk "{print \$2}"); 
        curl --http2 --compressed --max-time 30 --retry 3 -sSL "$url" > "'"$dl_dir"'/${idx}.tmp"
    '

    # 按序合并
    for f in $(ls "$dl_dir/"*.tmp | sort -V); do
        cat "$f" >> "$domain_file"
        echo "" >> "$domain_file" # 强制换行
    done
    rm -rf "$dl_dir"

    sed -i 's/\r//' "$domain_file"
    # 注意：确保你的 sort-*.py 脚本就在当前目录下，或者路径正确
    python3 "$script" "$domain_file"
    
    # 核心清理与格式化
    sed -i 's/^[[:space:].+]*//; s/[[:space:].+]*$//' "$domain_file"
    sed -n '/[a-zA-Z0-9]/ { /^#/! s/^/+./p }' "$domain_file" > "$mihomo_txt_file"

    awk '!seen[$0]++' "$mihomo_txt_file" > "$mihomo_txt_file.tmp" && mv "$mihomo_txt_file.tmp" "$mihomo_txt_file"

    # 使用全局变量 mihomo_tool 调用
    ./"$mihomo_tool" convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file"
    
    # 移动文件 (确保 ../txt 目录存在，如果不存在可能会报错，建议加 -p)
    mkdir -p ../txt
    mv "$mihomo_txt_file" "../txt/$mihomo_txt_file"
    mv "$mihomo_mrs_file" "../$mihomo_mrs_file"
}

# === 修改重点：替换为 DustinWin 源的下载逻辑 ===
setup_mihomo_tool() {
    log "正在下载 DustinWin 提供的 Mihomo (CrashCore) 工具..."
    
    # 对应原 Workflow 中的下载链接
    local download_url="https://github.com/DustinWin/proxy-tools/releases/download/mihomo/mihomo-meta-linux-amd64v3.tar.gz"
    
    # 下载并直接解压 (模拟 curl | tar 行为)
    curl -L "$download_url" | tar -zx
    
    # DustinWin 的包解压出来文件名是 CrashCore，需要重命名为 mihomo
    if [ -f "CrashCore" ]; then
        mv -f CrashCore mihomo
        chmod +x mihomo
        mihomo_tool="mihomo"  # 设置全局变量名
        log "Mihomo 工具准备就绪 (版本: DustinWin/amd64v3)"
    else
        error "下载或解压失败，未找到 CrashCore 文件"
        exit 1
    fi
}

# 执行主流程
setup_mihomo_tool

for name in "${!RULES[@]}"; do
    IFS=$'\n' read -r -d '' script urls <<< "${RULES[$name]}"
    urls=($urls)
    process_rules "$name" "$script" "${urls[@]}" &
done
wait

# 清理工作
rm -rf ./*.txt 
rm -f "$mihomo_tool"  # 删除 mihomo 二进制文件
# 注意：原脚本的 version.txt 清理已移除，因为此逻辑不需要 version.txt

log "脚本执行完成"
