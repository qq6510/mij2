import sys
import re
import tldextract

# 1. 定义需要过滤的国家域名后缀 (TLD)
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
    """提取 || 后的域名"""
    match = re.match(r'\|\|([a-zA-Z0-9.-]+)', rule)
    return match.group(1).lower() if match else None

def get_registered_domain(domain):
    """精准获取注册域名（用于最后排序）"""
    ext = tldextract.extract(domain)
    return f"{ext.domain}.{ext.suffix}" if ext.domain else domain

# --- 主程序 ---
file_name = sys.argv[1]
with open(file_name, 'r', encoding='utf8') as f:
    lines = f.readlines()

# 步骤 1: 提取域名并去重（Set）
raw_domains = set()
for line in lines:
    d = extract_domain(line.strip())
    if d:
        raw_domains.add(d)

# 步骤 2: 彻底去重（解决风险 B）
# 原理：先按长度从短到长排序。如果一个域名是已有域名的子域，则剔除。
# 例如：已有 example.com，后续的 a.example.com 和 a.b.example.com 都会被跳过。
sorted_list = sorted(list(raw_domains), key=len)
unique_domains = []

for d in sorted_list:
    # 检查 d 是否是 unique_domains 中任何一个域名的子域名
    # 必须匹配 ".parent.com" 结尾，防止误伤（如 abc.com 误伤 c.com）
    is_subdomain = any(d.endswith('.' + parent) for parent in unique_domains)
    
    if not is_subdomain:
        unique_domains.append(d)

# 步骤 3: 过滤黑名单后缀
filtered_domains = []
for d in unique_domains:
    ext = tldextract.extract(d)
    tld = ext.suffix.split('.')[-1]
    if tld not in REMOVE_TLD:
        filtered_domains.append(d)

# 步骤 4: 排序（按主域名聚类，方便阅读）
filtered_domains.sort(key=lambda d: (get_registered_domain(d), d))

# 步骤 5: 写入文件（纯域名格式）
with open(file_name, 'w', encoding='utf8') as f:
    for d in filtered_domains:
        f.writelines(f"{d}\n")


