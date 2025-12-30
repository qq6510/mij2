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
    """检查星号是否合法：星号必须独立成段"""
    if '*' not in domain:
        return True
    parts = domain.split('.')
    for p in parts:
        if '*' in p and p != '*':
            return False
    return True

def clean_wildcard_prefix(domain):
    """清理开头的 *. 以兼容 Shell 的 +. 逻辑"""
    cleaned = domain
    while cleaned.startswith('*') or cleaned.startswith('.'):
        cleaned = cleaned.lstrip('*').lstrip('.')
    return cleaned

def get_sort_key(domain):
    """获取排序键：按域名倒序段排序，例如 blog.google.com -> ('com', 'google', 'blog')"""
    return tuple(reversed(domain.split('.')))

def has_removable_tld(domain):
    """精确检查域名后缀是否在黑名单中"""
    d = domain.lower()
    for tld in REMOVE_TLD:
        if d == tld.lstrip('.') or d.endswith(tld):
            return True
    return False

def filter_subdomains(domains):
    """
    深度去重逻辑：如果父域名已存在，则剔除所有子域名。
    例如：已有 'google.com'，则删除 'mail.google.com'
    """
    # 按域名长度从小到大排序，确保父域名先被处理
    sorted_list = sorted(list(domains), key=len)
    final_set = []
    
    for d in sorted_list:
        # 检查当前域名是否是已存在域名的子域名
        # 逻辑：d 是 'a.b.com'，p 是 'b.com'，则 d.endswith('.' + p) 为 True
        if any(d.endswith('.' + p) for p in final_set):
            continue
        final_set.append(d)
    return set(final_set)

# 主程序
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <filename>")
        sys.exit(1)

    file_name = sys.argv[1]

    if not os.path.exists(file_name):
        print(f"Error: File {file_name} not found.")
        sys.exit(1)

    with open(file_name, 'r', encoding='utf8') as f:
        lines = f.readlines()

    # 第一阶段：提取与初步清洗
    raw_extracted = set()
    wildcard_mid_rules = set()

    for line in lines:
        line = line.strip()
        if line.startswith('||'):
            domain = extract_domain(line)
            if domain:
                domain_lower = domain.lower()
                if is_wildcard_valid(domain_lower):
                    clean_rule = clean_wildcard_prefix(domain_lower)
                    if clean_rule:
                        if '*' in clean_rule:
                            wildcard_mid_rules.add(clean_rule)
                        else:
                            raw_extracted.add(clean_rule)

    # 第二阶段：TLD 过滤
    standard_filtered = {r for r in raw_extracted if not has_removable_tld(r)}
    wildcard_filtered = {r for r in wildcard_mid_rules if not has_removable_tld(r)}

    # 第三阶段：深度父子级去重 (仅针对标准域名)
    final_standard = filter_subdomains(standard_filtered)

    # 第四阶段：合并与排序
    all_final = final_standard | wildcard_filtered
    
    # 排序：按照域名层级排序（例如所有 google.com 的子域排在一起）
    sorted_rules = sorted(all_final, key=get_sort_key)

    # 写入文件
    with open(file_name, 'w', encoding='utf8') as f:
        for r in sorted_rules:
            f.write(f"{r}\n")

    print(f"Processing complete. Output saved to {file_name}")
