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

# 定义规则源和对应的处理脚本
declare -A RULES=(
    [Ad]="sort-adblock.py
        https://raw.githubusercontent.com/qq6510/mij3/main/domains.txt
        https://raw.githubusercontent.com/Kuroba-Sayuki/FuLing-AdRules/refs/heads/Master/FuLingRules/FuLingBlockList.txt
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

# 函数：处理规则
process_rules() {
    local name=$1
    local script=$2
    shift 2
    local urls=("$@")
    local domain_file="${name}_domain.txt"
    local tmp_file="${name}_tmp.txt"
    local mihomo_txt_file="${name}_Mihomo.txt"
    local mihomo_mrs_file="${mihomo_txt_file%.txt}.mrs"

    log "开始处理规则: $name"

    # 初始化文件
    > "$domain_file"

    # 并行下载规则到临时文件
    > "$tmp_file"
    log "开始下载规则文件到临时文件: $tmp_file"
    
    printf "%s\n" "${urls[@]}" | xargs -P 16 -I {} sh -c 'curl --http2 --compressed --max-time 30 --retry 3 -sSL "{}" >> '"$tmp_file"'; echo "" >> '"$tmp_file"''

    if [ $? -ne 0 ]; then
        error "下载规则失败: $name"
        return 1
    fi
    log "规则文件下载完成: $tmp_file"

    # 合并并去重
    cat "$tmp_file" >> "$domain_file"
    rm -f "$tmp_file"
    log "规则文件已合并到: $domain_file"

    # 修复换行符并调用对应的 Python 脚本去重排序
    sed -i 's/\r//' "$domain_file"
    log "已修复换行符: $domain_file"

    python "$script" "$domain_file"
    if [ $? -ne 0 ]; then
        error "Python 脚本执行失败: $script"
        return 1
    fi
    log "Python 脚本执行完成: $script"

    # --- 核心修复部分 ---
    # 1. 移除可能存在的行首多余点号或加号（防止出现 +..com）
    # 2. 删除空白行
    # 3. 统一添加 +. 前缀
    sed -i 's/^[.+]*//' "$domain_file"
    sed '/^[[:space:]]*$/d; /^#/d; s/^/+./' "$domain_file" > "$mihomo_txt_file"
    # ------------------

    ./"$mihomo_tool" convert-ruleset domain text "$mihomo_txt_file" "$mihomo_mrs_file"
    if [ $? -ne 0 ]; then
        error "Mihomo 工具转换失败: $mihomo_txt_file"
        return 1
    fi
    log "Mihomo 工具转换完成: $mihomo_txt_file -> $mihomo_mrs_file"

    # 将生成的文件移动到 ../ 目录
    mv "$mihomo_txt_file" "../txt/$mihomo_txt_file"
    mv "$mihomo_mrs_file" "../$mihomo_mrs_file"
    log "已将生成文件移动到对应目录🙉: $mihomo_txt_file, $mihomo_mrs_file"
}

# 下载 Mihomo 工具
setup_mihomo_tool() {
    log "开始下载 Mihomo 工具"
    wget -q https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt
    if [ $? -ne 0 ]; then
        error "下载版本文件失败"
        exit 1
    fi

    version=$(cat version.txt)
    mihomo_tool="mihomo-linux-amd64-$version"

    wget -q "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/$mihomo_tool.gz"
    if [ $? -ne 0 ]; then
        error "下载 Mihomo 工具失败"
        exit 1
    fi

    gzip -d "$mihomo_tool.gz"
    chmod +x "$mihomo_tool"
    log "Mihomo 工具下载完成: $mihomo_tool"
}

# 主流程
setup_mihomo_tool

# 并行处理所有规则组
for name in "${!RULES[@]}"; do
    # 解析规则配置
    IFS=$'\n' read -r -d '' script urls <<< "${RULES[$name]}"
    urls=($urls) # 转为数组

    process_rules "$name" "$script" "${urls[@]}" &
done

# 等待所有规则并行处理完成
wait

# 清理缓存文件
rm -rf ./*.txt "$mihomo_tool" version.txt
log "脚本执行完成，已清理临时文件"
