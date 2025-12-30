import os
import sys
import re

# 定义需要过滤的国家域名后缀
REMOVE_TLD = {
    # 亚洲 (剔除了 .in, .id, .th, .vn, .ph 等广告/博彩高发区)
    ".my", ".pk", ".bd", ".lk", ".np", ".mn", ".uz", ".kz", ".kg", ".bt", ".mv", ".mm",

    # 欧洲 (剔除了 .ru，俄罗斯后缀是全球公认的恶意软件和广告重灾区)
    ".uk", ".de", ".fr", ".it", ".es", ".nl", ".be", ".ch", ".at", ".pl",
    ".cz", ".se", ".no", ".fi", ".dk", ".gr", ".pt", ".ie", ".hu", ".ro", ".bg",
    ".sk", ".si", ".lt", ".lv", ".ee", ".is", ".md", ".ua", ".by", ".am", ".ge",

    # 美洲
    ".us", ".ca", ".mx", ".br", ".ar", ".cl", ".co", ".pe", ".ve", ".uy", ".py",
    ".bo", ".ec", ".cr", ".pa", ".do", ".gt", ".sv", ".hn", ".ni", ".jm", ".cu",

    # 非洲
    ".za", ".eg", ".ng", ".ke", ".gh", ".tz", ".ug", ".dz", ".ma", ".tn", ".ly",
    ".ci", ".sn", ".zm", ".zw", ".ao", ".mz", ".bw", ".na", ".rw", ".mw", ".sd",

    # 大洋洲 (剔除了 .tk, .tv 等常用于非法流媒体或免费垃圾站的后缀)
    ".au", ".nz", ".fj", ".pg", ".sb", ".vu", ".nc", ".pf", ".ws", ".to", ".ki",
    ".nr", ".as",

    # 中东
    ".sa", ".ae", ".ir", ".il", ".iq", ".tr", ".sy", ".jo", ".lb", ".om", ".qa",
    ".ye", ".kw", ".bh"
}

def extract_domain(rule):
    """从 Adblock 规则中提取域名，支持通配符 * 并兼容结尾的 ^"""
    # 修改正则：允许星号 *，并将结尾的 ^ 设为可选匹配
    match = re.match(r'\|\|([a-zA-Z0-9.*-]+)\^?', rule)
    return match.group(1) if match else None

def get_parent_domain(domain):
    """获取父域名（最后两段）"""
    parts = domain.split('.')
    if len(parts) > 2:
        return '.'.join(parts[-2:])
    return domain

def has_removable_tld(domain):
    """检查域名是否以指定后缀结尾（大小写不敏感）"""
    d = domain.lower()
    return any(d.endswith(tld) for tld in REMOVE_TLD)

# 读取输入文件名
if len(sys.argv) < 2:
    print("Usage: python3 sort-adblock.py <filename>")
    sys.exit(1)

file_name = sys.argv[1]

# 打开文件并读取所有行
with open(file_name, 'r', encoding='utf8') as f:
    lines = f.readlines()

# 提取域名规则
domains = set()
for line in lines:
    line = line.strip()
    if line.startswith('||'):  # 只处理 || 开头的规则
        domain = extract_domain(line)
        if domain:
            domains.add(domain.lower())

# 分类处理：将标准域名和带通配符的域名分开
parent_domains = set()
subdomains = set()
wildcard_rules = set() # 专门存储带 * 的规则，不参与父子去重逻辑

for domain in domains:
    # 如果包含通配符，直接跳过复杂的层级去重，防止误删正常域名
    if '*' in domain:
        wildcard_rules.add(domain)
        continue
        
    parent_domain = get_parent_domain(domain)
    if parent_domain in parent_domains or domain == parent_domain:
        # 如果父域名已存在，或者当前域名本身是父域名
        continue
    if domain != parent_domain:
        # 如果是子域名，暂存到子域名集合
        subdomains.add(domain)
    else:
        # 否则添加到父域名集合
        parent_domains.add(parent_domain)

# 处理标准域名的子域名冲突
clean_domains = domains.copy()
for subdomain in subdomains:
    parent_domain = get_parent_domain(subdomain)
    if parent_domain in parent_domains:
        # 存在子域名时，保留父域名，移除子域名
        clean_domains.discard(subdomain)

# 合并标准规则与通配符规则
combined_domains = clean_domains | wildcard_rules

# 去除以指定后缀结尾的域名
filtered_domains = {domain for domain in combined_domains if not has_removable_tld(domain)}

# 排序规则：先按父域名排序，再按子域名排序
sorted_domains = sorted(
    filtered_domains,
    key=lambda d: (get_parent_domain(d.lower()), d.lower())
)

# 转换为每行一个域名的格式
domain_rules = [f"{domain}\n" for domain in sorted_domains]

# 写入文件
with open(file_name, 'w', encoding='utf8') as f:
    f.writelines(domain_rules)
