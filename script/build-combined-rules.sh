import os
import sys
import re

# 定义需要过滤的国家域名后缀
REMOVE_TLD = {
    # 亚洲
    ".my", ".pk", ".bd", ".lk", ".np", ".mn", ".uz", ".kz", ".kg", ".bt", ".mv", ".mm",
    # 欧洲
    ".uk", ".de", ".fr", ".it", ".es", ".nl", ".be", ".ch", ".at", ".pl",
    ".cz", ".se", ".no", ".fi", ".dk", ".gr", ".pt", ".ie", ".hu", ".ro", ".bg",
    ".sk", ".si", ".lt", ".lv", ".ee", ".is", ".md", ".ua", ".by", ".am", ".ge",
    # 美洲
    ".us", ".ca", ".mx", ".br", ".ar", ".cl", ".co", ".pe", ".ve", ".uy", ".py",
    ".bo", ".ec", ".cr", ".pa", ".do", ".gt", ".sv", ".hn", ".ni", ".jm", ".cu",
    # 非洲
    ".za", ".eg", ".ng", ".ke", ".gh", ".tz", ".ug", ".dz", ".ma", ".tn", ".ly",
    ".ci", ".sn", ".zm", ".zw", ".ao", ".mz", ".bw", ".na", ".rw", ".mw", ".sd",
    # 大洋洲
    ".au", ".nz", ".fj", ".pg", ".sb", ".vu", ".nc", ".pf", ".ws", ".to", ".ki",
    ".nr", ".as",
    # 中东
    ".sa", ".ae", ".ir", ".il", ".iq", ".tr", ".sy", ".jo", ".lb", ".om", ".qa",
    ".ye", ".kw", ".bh"
}

# --- 扩充后的多级后缀清单 ---
# 包含常见的二后缀组合，防止 get_parent_domain 错误切割
MULTI_LEVEL_SUFFIXES = {
    # 中国
    "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "ac.cn",
    # 香港/台湾
    "com.hk", "org.hk", "edu.hk", "com.tw", "org.tw", "edu.tw",
    # 英国
    "co.uk", "me.uk", "org.uk", "sch.uk", "ac.uk", "gov.uk",
    # 日本/韩国
    "co.jp", "ad.jp", "ne.jp", "co.kr", "or.kr", "go.kr",
    # 澳大利亚
    "com.au", "net.au", "org.au", "edu.au", "gov.au",
    # 其他常见
    "com.br", "co.id", "com.my", "com.sg", "com.mx", "co.za"
}

def extract_domain(rule):
    """从 Adblock 规则中提取域名"""
    match = re.match(r'\|\|([a-zA-Z0-9.-]+)', rule)
    return match.group(1) if match else None

def get_parent_domain(domain):
    """
    改进版获取父域名：支持复合后缀
    逻辑：如果域名最后两段属于复合后缀，则取三段作为父域名；否则取两段。
    """
    parts = domain.split('.')
    if len(parts) <= 2:
        return domain
    
    # 获取最后两段进行判定，例如 'com.cn'
    last_two_parts = ".".join(parts[-2:])
    
    if last_two_parts in MULTI_LEVEL_SUFFIXES:
        # 如果是复合后缀，父域名应该是最后三段 (例如 example.com.cn)
        if len(parts) >= 3:
            return ".".join(parts[-3:])
    
    # 默认逻辑：取最后两段 (例如 example.com)
    return ".".join(parts[-2:])

def has_removable_tld(domain):
    """检查域名是否以指定后缀结尾（大小写不敏感）"""
    d = domain.lower()
    return any(d.endswith(tld) for tld in REMOVE_TLD)

# --- 主程序逻辑 ---

# 检查命令行参数
if len(sys.argv) < 2:
    print("使用方法: python script.py <文件名>")
    sys.exit(1)

file_name = sys.argv[1]

# 读取文件
with open(file_name, 'r', encoding='utf8') as f:
    lines = f.readlines()

# 提取域名规则
domains = set()
for line in lines:
    line = line.strip()
    if line.startswith('||'):
        domain = extract_domain(line)
        if domain:
            domains.add(domain.lower())

# --- 核心：去除子域名，保留父域名的逻辑 (维持原样) ---
parent_domains = set()
subdomains = set()

for domain in domains:
    parent_domain = get_parent_domain(domain)
    if parent_domain in parent_domains or domain == parent_domain:
        # 如果父域名已存在，或者当前域名本身是父域名
        if domain == parent_domain:
            parent_domains.add(domain)
        continue
    
    if domain != parent_domain:
        # 如果是子域名，暂存到子域名集合
        subdomains.add(domain)
    else:
        # 否则添加到父域名集合
        parent_domains.add(parent_domain)

# 从父域名集合中移除与子域名冲突的（实际是从主集合中舍弃子域名）
for subdomain in subdomains:
    parent_domain = get_parent_domain(subdomain)
    if parent_domain in parent_domains:
        domains.discard(subdomain)

# 去除以指定后缀结尾的域名
filtered_domains = {domain for domain in domains if not has_removable_tld(domain)}

# 排序规则：先按父域名排序，再按完整域名排序
sorted_domains = sorted(
    filtered_domains,
    key=lambda d: (get_parent_domain(d.lower()), d.lower())
)

# 还原为 ||domain^ 格式（你原始代码末尾注释为 domain 格式，此处按通用标准还原）
domain_rules = [f"||{domain}^\n" for domain in sorted_domains]

# 写入文件
with open(file_name, 'w', encoding='utf8') as f:
    f.writelines(domain_rules)

print(f"处理完成！输出文件: {file_name}")
