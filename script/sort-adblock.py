import sys
import re
import tldextract

# 1. 你定义的需要过滤的国家域名后缀 (顶级域名 TLD)
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

def get_true_parent_domain(domain):
    """
    使用 tldextract 精准提取父域名（注册域名）
    例如: 'sub.example.com.cn' -> 'example.com.cn'
    """
    ext = tldextract.extract(domain)
    if ext.domain and ext.suffix:
        return f"{ext.domain}.{ext.suffix}"
    return domain

def is_blacklisted_tld(domain):
    """检查顶级后缀是否在拦截名单中"""
    ext = tldextract.extract(domain.lower())
    # 提取最后的顶级后缀（如 com.cn 提取出 cn）
    tld = ext.suffix.split('.')[-1]
    return tld in REMOVE_TLD

# --- 主程序逻辑 ---

file_name = sys.argv[1]

with open(file_name, 'r', encoding='utf8') as f:
    lines = f.readlines()

# 第一步：初步提取并转小写去重
initial_domains = set()
for line in lines:
    line = line.strip()
    if line.startswith('||'):
        domain = extract_domain(line)
        if domain:
            initial_domains.add(domain.lower())

# 第二步：【执行你的父子去重逻辑】
# 找出所有的父域名
parent_domains_found = set()
for d in initial_domains:
    parent = get_true_parent_domain(d)
    if d == parent:
        parent_domains_found.add(d)

# 核心去重：如果一个域名是子域名，且它的父域名已经在列表里，就标记为待删除
final_domains = initial_domains.copy()
for d in initial_domains:
    parent = get_true_parent_domain(d)
    if d != parent and parent in parent_domains_found:
        final_domains.discard(d)

# 第三步：【执行后缀过滤】
filtered_domains = {d for d in final_domains if not is_blacklisted_tld(d)}

# 第四步：排序
sorted_domains = sorted(
    filtered_domains,
    key=lambda d: (get_true_parent_domain(d), d)
)

# 第五步：写入
with open(file_name, 'w', encoding='utf8') as f:
    for d in sorted_domains:
        f.write(f"||{d}^\n")

print(f"处理完成！")
