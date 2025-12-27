import sys
import re
import tldextract

# 1. 拦截的国家域名后缀 (顶级域名 TLD)
REMOVE_TLD = {
    "my", "pk", "bd", "lk", "np", "mn", "uz", "kz", "kg", "bt", "mv", "mm",
    "uk", "de", "fr", "it", "es", "nl", "be", "ch", "at", "pl",
    "cz", "se", "no", "fi", "dk", "gr", "pt", "ie", "hu", "ro", "bg",
    "sk", "si", "lt", "lv", "ee", "is", "md", "ua", "by", "am", "ge",
    "us", "ca", "mx", "br", "ar", "cl", "co", "pe", "ve", "uy", "py",
    "bo", "ec", "cr", "pa", "do", "gt", "sv", "hn", "ni", "jm", "cu",
    "za", "eg", "ng", "ke", "gh", "tz", "ug", "dz", "ma", "tn", "ly",
    "ci", "sn", "zm", "zw", "ao", "mz", "bw", "na", "rw", "mw", "sd",
    "au", "nz", "fj", "pg", "sb", "vu", "nc", "pf", "ws", "to", "ki",
    "nr", "as", "sa", "ae", "ir", "il", "iq", "tr", "sy", "jo", "lb", 
    "om", "qa", "ye", "kw", "bh"
}

def extract_domain(rule):
    """从 Adblock 规则中提取域名部分"""
    match = re.match(r'\|\|([a-zA-Z0-9.-]+)', rule)
    return match.group(1) if match else None

def get_registered_domain(domain):
    """
    使用 tldextract 精准提取注册域名 (Root Domain)
    例如: 'sub.example.com.cn' -> 'example.com.cn'
    """
    ext = tldextract.extract(domain)
    if ext.domain and ext.suffix:
        return f"{ext.domain}.{ext.suffix}"
    return domain

def is_blacklisted_tld(domain):
    """检查顶级后缀是否在拦截名单中"""
    ext = tldextract.extract(domain.lower())
    tld = ext.suffix.split('.')[-1]
    return tld in REMOVE_TLD

# --- 主程序逻辑 ---

if len(sys.argv) < 2:
    print("使用方法: python script.py <文件名>")
    sys.exit(1)

file_name = sys.argv[1]

# 读取文件
with open(file_name, 'r', encoding='utf8') as f:
    lines = f.readlines()

# 第一步：提取并统一转小写去重
initial_domains = set()
for line in lines:
    line = line.strip()
    if line.startswith('||'):
        domain = extract_domain(line)
        if domain:
            initial_domains.add(domain.lower())

# 第二步：深度去重（子域名剔除）
# 逻辑：如果列表里有 example.com，那么 www.example.com 就会被剔除
# 为了性能，先按域名长度排序，短的（父域名）在前
sorted_by_len = sorted(list(initial_domains), key=len)
minimal_domains = []
for d in sorted_by_len:
    # 检查当前域名是否是已经加入列表域名的子域名
    if not any(d.endswith('.' + parent) for parent in minimal_domains):
        # 补充逻辑：也要防止 d 本身就是 parent（因为 set 已经去重，这里主要是后缀判定）
        if d not in minimal_domains:
            minimal_domains.append(d)

# 第三步：后缀过滤
# 过滤掉属于 REMOVE_TLD 的域名
filtered_domains = [d for d in minimal_domains if not is_blacklisted_tld(d)]

# 第四步：排序（优化性能：预计算排序键，避免在 sorted 中反复调用 tldextract）
# 排序规则：主域名字母序 -> 全域名字母序
sort_precomputed = []
for d in filtered_domains:
    sort_precomputed.append((get_registered_domain(d), d))

sort_precomputed.sort()

# 第五步：写入（按第二段代码的正确格式输出）
with open(file_name, 'w', encoding='utf8') as f:
    for _, domain in sort_precomputed:
        f.write(f"{domain}\n")

print(f"处理完成！输出共 {len(filtered_domains)} 条规则。")
