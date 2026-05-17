import os
import sys
import re

# 优化 4.1：预编译正则表达式，避免循环中重复编译
DOMAIN_PATTERN = re.compile(r'\|\|([a-zA-Z0-9.*-]+)\^?')

# 定义需要过滤的国家域名后缀集合
REMOVE_TLD_SET = {
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
# 优化 2.1：转换为元组，供底层的 endswith 直接使用
REMOVE_TLD_TUPLE = tuple(REMOVE_TLD_SET)


def extract_domain(rule):
    """从 Adblock 规则中提取域名部分"""
    match = DOMAIN_PATTERN.match(rule)
    return match.group(1) if match else None


def is_wildcard_valid(domain):
    """检查星号是否合法：星号必须独立成段"""
    if '*' not in domain:
        return True
    for p in domain.split('.'):
        if '*' in p and p != '*':
            return False
    return True


def clean_wildcard_prefix(domain):
    """清理开头的 *. 以兼容 Shell 的 +. 逻辑"""
    # 优化 3：lstrip 自动处理所有指定的字符集，无需 while 循环
    return domain.lstrip('*.')


def get_sort_key(domain):
    """获取排序键：按域名倒序段排序"""
    return tuple(reversed(domain.split('.')))


def has_removable_tld(domain):
    """精确检查域名后缀是否在黑名单中"""
    d = domain.lower()
    # 优化 2.2：利用哈希匹配和 C 底层元组匹配替代 for 循环
    return d.endswith(REMOVE_TLD_TUPLE) or ('.' + d) in REMOVE_TLD_SET


def filter_subdomains(domains):
    """深度去重逻辑：如果父域名已存在，则剔除所有子域名。"""
    if not domains:
        return set()
    
    # 优化 1：使用倒序字符串排序，将 O(N^2) 复杂度降为 O(N log N)
    sorted_domains = sorted(domains, key=lambda d: d[::-1])
    final_list = []
    
    for d in sorted_domains:
        if not final_list or not d.endswith('.' + final_list[-1]):
            final_list.append(d)
    return set(final_list)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <filename>")
        sys.exit(1)

    file_name = sys.argv[1]

    if not os.path.exists(file_name):
        print(f"Error: File {file_name} not found.")
        sys.exit(1)

    raw_extracted = set()
    wildcard_mid_rules = set()

    # 优化 4.2：直接迭代文件对象，避免 readlines() 打爆内存
    with open(file_name, 'r', encoding='utf8') as f:
        for line in f:
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

    standard_filtered = {r for r in raw_extracted if not has_removable_tld(r)}
    wildcard_filtered = {r for r in wildcard_mid_rules if not has_removable_tld(r)}

    final_standard = filter_subdomains(standard_filtered)

    all_final = final_standard | wildcard_filtered
    sorted_rules = sorted(all_final, key=get_sort_key)

    with open(file_name, 'w', encoding='utf8') as f:
        # 优化 4.3：利用生成器表达式和 writelines 提升 I/O 写入性能
        f.writelines(f"{r}\n" for r in sorted_rules)

    print(f"Processing complete. Output saved to {file_name}")
