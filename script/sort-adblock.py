import os
import sys
import re

# --- 你的 REMOVE_TLD 保持不变 ---
REMOVE_TLD = {
    ".my", ".pk", ".bd", ".lk", ".np", ".mn", ".uz", ".kz", ".kg", ".bt", ".mv", ".mm",
    ".uk", ".de", ".fr", ".it", ".es", ".nl", ".be", ".ch", ".at", ".pl",
    ".cz", ".se", ".no", ".fi", ".dk", ".gr", ".pt", ".ie", ".hu", ".ro", ".bg",
    ".sk", ".si", ".lt", ".lv", ".ee", ".is", ".md", ".ua", ".by", ".am", ".ge",
    ".us", ".ca", ".mx", ".br", ".ar", ".cl", ".co", ".pe", ".ve", ".uy", ".py",
    ".bo", ".ec", ".cr", ".pa", ".do", ".gt", ".sv", ".hn", ".ni", ".jm", ".cu",
    ".za", ".eg", ".ng", ".ke", ".gh", ".tz", ".ug", ".dz", ".ma", ".tn", ".ly",
    ".ci", ".sn", ".zm", ".zw", ".ao", ".mz", ".bw", ".na", ".rw", ".mw", ".sd",
    ".au", ".nz", ".fj", ".pg", ".sb", ".vu", ".nc", ".pf", ".ws", ".to", ".ki",
    ".nr", ".as", ".sa", ".ae", ".ir", ".il", ".iq", ".tr", ".sy", ".jo", ".lb", 
    ".om", ".qa", ".ye", ".kw", ".bh"
}

# --- 新增：手动定义常见的多级后缀 ---
# 这样不需要安装 tldextract 也能识别 .com.cn
MULTI_LEVEL_SUFFIXES = {
    ".com.cn", ".net.cn", ".org.cn", ".gov.cn", ".edu.cn", 
    ".com.hk", ".org.hk", ".co.jp", ".co.uk", ".co.kr", ".com.tw"
}

def extract_domain(rule):
    """从 Adblock 规则中提取域名"""
    match = re.match(r'\|\|([a-zA-Z0-9.-]+)', rule)
    return match.group(1) if match else None

# --- 你的核心函数优化：兼容 .com.cn ---
def get_parent_domain(domain):
    """获取真正的父域名"""
    parts = domain.split('.')
    if len(parts) <= 2:
        return domain
    
    # 检查最后两段是否构成了复合后缀（如 .com.cn）
    last_two = "." + ".".join(parts[-2:])
    if last_two in MULTI_LEVEL_SUFFIXES:
        # 如果是复合后缀，父域名应该是最后三段 (例如 example.com.cn)
        if len(parts) >= 3:
            return ".".join(parts[-3:])
    
    # 否则按你原始的逻辑：取最后两段 (例如 example.com)
    return ".".join(parts[-2:])

def has_removable_tld(domain):
    """检查域名是否以指定后缀结尾"""
    d = domain.lower()
    return any(d.endswith(tld) for tld in REMOVE_TLD)

# --- 以下部分完全保留你的原始循环逻辑，不作任何简化 ---

file_name = sys.argv[1]

with open(file_name, 'r', encoding='utf8') as f:
    lines = f.readlines()

domains = set()
for line in lines:
    line = line.strip()
    if line.startswith('||'):
        domain = extract_domain(line)
        if domain:
            domains.add(domain.lower())

parent_domains = set()
subdomains = set()

# 这里是你原始的子域名/父域名去重循环
for domain in domains:
    parent_domain = get_parent_domain(domain)
    if parent_domain in parent_domains or domain == parent_domain:
        # 如果父域名已存在，或者当前域名本身是父域名
        if domain == parent_domain:
            parent_domains.add(parent_domain) # 修正你的逻辑：确保父域名入集
        continue
    if domain != parent_domain:
        subdomains.add(domain)
    else:
        parent_domains.add(parent_domain)

for subdomain in subdomains:
    parent_domain = get_parent_domain(subdomain)
    if parent_domain in parent_domains:
        domains.discard(subdomain)

filtered_domains = {domain for domain in domains if not has_removable_tld(domain)}

sorted_domains = sorted(
    filtered_domains,
    key=lambda d: (get_parent_domain(d.lower()), d.lower())
)

domain_rules = [f"||{domain}^\n" for domain in sorted_domains]

with open(file_name, 'w', encoding='utf8') as f:
    f.writelines(domain_rules)
