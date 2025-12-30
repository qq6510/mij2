import os
import sys
import re

# 定义需要过滤的国家域名后缀
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
    ".nr", ".as",
    ".sa", ".ae", ".ir", ".il", ".iq", ".tr", ".sy", ".jo", ".lb", ".om", ".qa",
    ".ye", ".kw", ".bh"
}

def extract_domain(rule):
    """从 Adblock 规则中提取域名部分"""
    match = re.match(r'\|\|([a-zA-Z0-9.*-]+)\^?', rule)
    return match.group(1) if match else None

def is_wildcard_valid(domain):
    """
    检查星号是否合法：星号必须独立成段（如 * 或 .*.），不能与字母粘连。
    """
    if '*' not in domain:
        return True
    parts = domain.split('.')
    for p in parts:
        if '*' in p and p != '*':
            return False
    return True

def clean_wildcard_prefix(domain):
    """
    为了配合 Shell 脚本的 +. 逻辑：
    1. 将 *.bllst.cn 处理为 bllst.cn (Shell 加上 +. 后变成 +.bllst.cn)
    2. 将 .*.co 处理为 co (Shell 加上 +. 后变成 +.co)
    3. 中间带星号的如 fbia.*.cn 则保持原样
    """
    if not domain.startswith('*') and not domain.startswith('.'):
        return domain
    
    # 递归去掉开头的 * 和 .
    cleaned = domain
    while cleaned.startswith('*') or cleaned.startswith('.'):
        cleaned = cleaned.lstrip('*').lstrip('.')
    return cleaned

def get_parent_domain(domain):
    """获取父域名（最后两段）"""
    parts = domain.split('.')
    if len(parts) > 2:
        return '.'.join(parts[-2:])
    return domain

def has_removable_tld(domain):
    """检查域名是否以指定后缀结尾"""
    d = domain.lower()
    return any(d.endswith(tld) for tld in REMOVE_TLD)

# 主程序逻辑
if len(sys.argv) < 2:
    sys.exit(1)

file_name = sys.argv[1]

with open(file_name, 'r', encoding='utf8') as f:
    lines = f.readlines()

processed_rules = set()
for line in lines:
    line = line.strip()
    if line.startswith('||'):
        domain = extract_domain(line)
        if domain:
            domain_lower = domain.lower()
            # 1. 验证星号是否粘连字母
            if is_wildcard_valid(domain_lower):
                # 2. 清理开头的 *. 以兼容 Shell 的 +. 逻辑
                final_rule = clean_wildcard_prefix(domain_lower)
                if final_rule:
                    processed_rules.add(final_rule)

# 区分标准域名和带中间星号的域名
standard_domains = set()
wildcard_mid_rules = set()

for rule in processed_rules:
    if '*' in rule:
        wildcard_mid_rules.add(rule)
    else:
        standard_domains.add(rule)

# 对标准域名执行父子级去重
parent_domains = set()
subdomains = set()

for d in standard_domains:
    parent = get_parent_domain(d)
    if d == parent:
        parent_domains.add(d)
    else:
        subdomains.add(d)

final_standard = parent_domains.copy()
for sub in subdomains:
    parent = get_parent_domain(sub)
    if parent not in parent_domains:
        final_standard.add(sub)

# 合并所有规则
all_final = final_standard | wildcard_mid_rules

# TLD 过滤与排序
filtered_rules = {r for r in all_final if not has_removable_tld(r)}

# 排序逻辑：按父域名维度排序
sorted_rules = sorted(
    filtered_rules,
    key=lambda r: (get_parent_domain(r), r)
)

# 写入文件
with open(file_name, 'w', encoding='utf8') as f:
    for r in sorted_rules:
        f.write(f"{r}\n")
