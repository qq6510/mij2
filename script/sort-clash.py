import sys
import re
import os

# 保持宽松字符集验证 (兼容 * 和 _)
VALID_CHARS_PATTERN = re.compile(r'^[a-zA-Z0-9._*-]+$')

def extract_domain_simple(line):
    """
    精简版本：直接返回单个有效域名字符串或 None。
    一步到位清理 YAML/Mihomo 规则前缀。
    """
    line = line.strip()
    
    # 1. 快速过滤无效行 (通过提取公共前缀精简了元组)
    if not line or 'regexp' in line or line.startswith((
        'payload:', '#', '!', 'DOMAIN', 'IP-CIDR'
    )):
        return None

    # 2. 核心修改：一步到位移除左侧可能存在的各种前缀符号
    # 涵盖: '+.', '.', '- \', '- ' 等，且绝对不影响右侧
    domain = line.lstrip('+- .\\').strip()

    # 3. 核心排除：通用匹配过滤
    if domain == '*':
        print(f"🚨 警告: 规则 '{line}' 被识别为通用匹配，已排除。")
        return None

    # 4. 最终字符集校验
    if domain and VALID_CHARS_PATTERN.match(domain):
        return domain

    return None

def process_file_sync(file_path):
    """
    同步处理整个文件，提取所有域名规则。
    """
    domains = set()
    
    try:
        with open(file_path, 'r', encoding='utf8', errors='ignore') as f:
            for line in f:
                # 简化接收逻辑，极大降低内存分配开销
                domain = extract_domain_simple(line)
                if domain:
                    domains.add(domain)
    except FileNotFoundError:
        print(f"❌ 错误：文件未找到: {file_path}")
    except Exception as e:
        print(f"❌ 读取文件时发生错误: {e}")
        
    return domains

def remove_subdomains(domains):
    """
    移除子域名，只保留父域名（利用字符串倒序排序法，O(N log N) 高效去重）
    """
    if not domains:
        return set()
        
    sorted_domains = sorted(domains, key=lambda d: d[::-1])  
    result = []
    
    for domain in sorted_domains:
        if not result or not domain.endswith("." + result[-1]):
            result.append(domain)
    return set(result)

def main():
    if len(sys.argv) < 2:
        print("请提供输入文件路径作为参数")
        return

    file_name = sys.argv[1]
    print(f"🔍 正在以同步方式处理文件: {file_name}")

    domains = process_file_sync(file_name)

    if not domains:
        print("处理完成，未提取到有效域名。")
        return

    print(f"✅ 初步提取完成，有效规则数量: {len(domains)}")

    filtered_domains = remove_subdomains(domains)
    print(f"✂️ 去除子域名后剩余数量: {len(filtered_domains)}")

    # 排序写入，保证差异比对时的一致性
    sorted_domains = sorted(filtered_domains)

    try:
        with open(file_name, 'w', encoding='utf8') as f:
            f.writelines(f"{domain}\n" for domain in sorted_domains) 
        print(f"💾 处理完成！已覆盖写入文件：{file_name}，最终规则数：{len(sorted_domains)}")
        print("💡 注意：输出结果是干净的域名（不含 '+.'），如果需要转换内核规则，请记得手动或通过脚本添加前缀。")
    except Exception as e:
        print(f"❌ 写入文件时发生错误: {e}")

if __name__ == "__main__":
    main()
