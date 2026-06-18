#!/bin/bash

# 确保脚本切换到当前执行目录
cd "$(cd "$(dirname "$0")"; pwd)"

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
    [AI]="sort-clash.py
        https://raw.githubusercontent.com/DustinWin/ruleset_geodata/mihomo-ruleset/ai.list
        https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/github.list
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

    # 1. 纯 Bash 并发异步下载组内所有 URL
    local idx=1
    for url in "${urls[@]}"; do
        # 【核心修正】：利用 xargs 清洗掉配置文本中可能存在的前导缩进空格与尾随换行
        url=$(echo "$url" | xargs)
        
        # 安全卡口：如果遇到空行则跳过，防止产生无效请求
        [[ -z "$url" ]] && continue
        
        curl --http2 --compressed --max-time 30 --retry 3 -sSL "$url" > "$dl_dir/${idx}.tmp" &
        ((idx++))
    done
    wait 

    # 2. 严格按固定索引顺序追加拼合
    local i
    for ((i=1; i<idx; i++)); do
        if [[ -f "$dl_dir/${i}.tmp" ]]; then
            cat "$dl_dir/${i}.tmp" >> "$domain_file"
            echo "" >> "$domain_file"
        fi
    done
    rm -rf "$dl_dir"

    # 3. 交付 Python 进行去重与子域名裁剪
    sed -i 's/\r//' "$domain_file"
    if ! python3 "$script" "$domain_file"; then
        error "Python 清洗脚本 $script 执行失败 ($name)，跳过此组后续转换。"
        return 1
    fi
    
    # 4. 直接通过单行系统级 sed 批量披上 Mihomo 标准格式 (+.domain.com) 外衣
    sed 's/^/+./' "$domain_file" > "$mihomo_txt_file"

    # 5. 调用内核转换二进制 ruleset (.mrs)
    if ! "$mihomo_tool" convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file"; then
        error "Mihomo 编译 ruleset 失败 ($name)"
        return 1
    fi
    
    # 6. 移动归档
    mkdir -p ../txt
    mv "$mihomo_txt_file" "../txt/$mihomo_txt_file"
    mv "$mihomo_mrs_file" "../$mihomo_mrs_file"
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
        mihomo_tool="./mihomo"
        log "Mihomo 工具准备就绪 (运行测试通过)"
    else
        error "配置失败，解压后的二进制文件无法在当前系统运行。"
        exit 1
    fi
}

# 部署转换内核
setup_mihomo_tool

# 遍历大组并进行并发处理
for name in "${!RULES[@]}"; do
    # 利用 mapfile 优雅按行切分
    mapfile -t lines <<< "${RULES[$name]}"
    script="${lines[0]}"
    urls=("${lines[@]:1}")

    process_rules "$name" "$script" "${urls[@]}" &
done
wait

# 清理当前工作区临时残留
rm -rf ./*.txt 
rm -f "$mihomo_tool"

log "脚本执行完成"
