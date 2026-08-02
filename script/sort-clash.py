import re
import sys

# 1. 针对已统一转为小写的域名，简化正则匹配范围（提升正则匹配速度）
VALID_CHARS_PATTERN = re.compile(r"^[a-z0-9._*-]+$")


def extract_domain_simple(line):
    """直接返回单个有效域名字符串或 None。

    一步到位清理 YAML/Mihomo 规则前缀。
    """
    line = line.strip()

    # 1. 快速过滤无效行或非域名行
    if not line or "regexp" in line or line.startswith(("payload:", "#", "!", "DOMAIN", "IP-CIDR")):
        return None

    # 2. 剥离前缀符号并全量转为小写（解决大小写归一化隐患 [隐患2]）
    domain = line.lstrip("+- .\\").strip().lower()

    # 3. 核心排除：通用全匹配过滤，防止断网
    if domain == "*":
        print(f"🚨 警告: 规则 '{line}' 被识别为通用匹配，已排除。")
        return None

    # 4. 最终字符集合法校验
    if domain and VALID_CHARS_PATTERN.match(domain):
        return domain

    return None


def process_file_sync(file_path):
    """同步流式处理整个文件，提取所有域名."""
    domains = set()

    try:
        with open(file_path, "r", encoding="utf8", errors="ignore") as f:
            for line in f:
                domain = extract_domain_simple(line)
                if domain:
                    domains.add(domain)
    except FileNotFoundError:
        print(f"❌ 错误：文件未找到: {file_path}")
    except Exception as e:
        print(f"❌ 读取文件时发生错误: {e}")

    return domains


def remove_subdomains(domains):
    """移除冗余子域名，只保留最上级父域名。

    性能优化版：消除了循环内部重复拼接字符串和访问列表尾部的开销。
    """
    if not domains:
        return set()

    # 按倒序字符排序：父域名（如 moc.a）必排在其子域名（如 moc.a.b）前面
    sorted_domains = sorted(domains, key=lambda d: d[::-1])
    result = []

    # 缓存上一个匹配到的父域名后缀，避免在成千上万次循环中重复执行 "." + result[-1]
    last_root_suffix = None

    for domain in sorted_domains:
        if last_root_suffix is None or not domain.endswith(last_root_suffix):
            result.append(domain)
            last_root_suffix = "." + domain

    return set(result)


def main():
    if len(sys.argv) < 2:
        print("请提供输入文件路径作为参数")
        return

    file_name = sys.argv[1]
    print(f"🔍 正在处理文件: {file_name}")

    domains = process_file_sync(file_name)

    if not domains:
        print("处理完成，未提取到有效域名。")
        return

    print(f"✅ 初步提取完成，有效原始规则数量: {len(domains)}")

    filtered_domains = remove_subdomains(domains)
    print(f"✂️ 去除冗余子域名后剩余数量: {len(filtered_domains)}")

    # 排序输出，保证差异比对 (Git Diff) 时的一致性
    sorted_domains = sorted(filtered_domains)

    try:
        with open(file_name, "w", encoding="utf8") as f:
            f.writelines(f"{domain}\n" for domain in sorted_domains)
        print(
            f"💾 处理完成！已覆盖写入文件：{file_name}，最终规则数：{len(sorted_domains)}"
        )
    except Exception as e:
        print(f"❌ 写入文件时发生错误: {e}")


if __name__ == "__main__":
    main()
