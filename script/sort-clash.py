import sys
import re
import os

# 定义用于严格验证域名的字符集（字母、数字、点、减号）。
# 保持与上一版本相同的分离逻辑和宽松字符集（兼容 * 和 _）。
VALID_CHARS_PATTERN = re.compile(r'^[a-zA-Z0-9._*-]+$')

def extract_domain_simple(line):
    """
    更新版本：简化域名提取逻辑，专门处理每行一个域名，且可能带有 '+', '.' 前缀的情况，
    并增加对 '.*' 或 '+.*' 规则的明确排除。
    
    重点修改: 移除 '.' in domain 的强制要求，以支持提取 +.jp 这样的 TLD。
    
    返回: List[str] (有效域名列表)
    """
    line = line.strip()
    
    # 1. 快速过滤无效行 
    if 'regexp' in line:
        return []
    if not line or line.startswith((
        'payload:', '#', '!', 'DOMAIN,', 'DOMAIN-KEYWORD,',
        'DOMAIN-SUFFIX,', 'IP-CIDR,', 'IP-CIDR6,'
    )):
        return []

    # --- 核心修改部分：去除前缀，提取域名 ---

    temp_line = line
    
    # 步骤 A: 移除常见的前缀，例如 '+.', ' +.', ' - \', ' - '
    
    # 优先去除 Mihomo 规则中常见的 '+' 前缀
    if temp_line.startswith('+'):
        temp_line = temp_line[1:].strip()
    
    # 继续去除可能的 '.' 符号
    if temp_line.startswith('.'):
        temp_line = temp_line[1:].strip()

    # 核心排除：如果去除前缀后只剩下 '*'，则明确排除这条规则 (即排除 '+.*' 或 '.*')
    if temp_line == '*':
        print(f"🚨 警告: 规则 '{line}' 被识别为通用匹配，已排除。")
        return []

    # 处理原脚本中提到的 ' - \' 或 '  - \' 格式
    if temp_line.startswith('- \\') or temp_line.startswith('  - \\'):
        domain = temp_line.strip('- \\').strip()
    else:
        domain = temp_line.strip() # 最终清理空白字符
    
    # --- 最终检查 ---
    
    valid_domains = set()

    # 检查 1: 确保不是空字符串
    if domain:
        # **【关键修改】**：移除了 `'.' in domain` 的检查。
        # 现在，如 'jp' 这样的字符串也能通过检查。
        
        # 检查 2: 确保符合字符规范 (兼容 * 和 _)
        if VALID_CHARS_PATTERN.match(domain):
            valid_domains.add(domain)

    return list(valid_domains)


# --- 后续函数保持不变 ---

def process_file_sync(file_path):
    """
    同步处理整个文件，提取所有域名规则。
    """
    domains = set()
    
    try:
        with open(file_path, 'r', encoding='utf8', errors='ignore') as f:
            for line in f:
                # 调用修改后的提取函数
                extracted_list = extract_domain_simple(line)
                if extracted_list:
                    domains.update(extracted_list)
    except FileNotFoundError:
        print(f"❌ 错误：文件未找到: {file_path}")
        return set()
    except Exception as e:
        print(f"❌ 读取文件时发生错误: {e}")
        return set()
        
    return domains

def remove_subdomains(domains):
    """
    移除子域名，只保留父域名
    
    注意：在支持 TLD/SLD 后（如 'jp'），父域名逻辑仍然成立。
    例如：存在 'jp' 和 'co.jp'，'co.jp' 不以 '.jp' 结尾，两者都会被保留。
    如果存在 'test.co.jp' 和 'co.jp'，'test.co.jp' 会被移除。
    """
    if not domains:
        return set()
        
    # 按域名倒序排序：例如 abc.com, c.abc.com, b.abc.com
    # 排序后变成：c.abc.com, b.abc.com, abc.com
    sorted_domains = sorted(domains, key=lambda d: d[::-1])  
    result = []
    
    for domain in sorted_domains:
        # 检查当前域名是否是上一个保留域名的子域名。
        # 由于是倒序检查，如果 domain 以 "." + result[-1] 结尾，则是子域名。
        if not result or not domain.endswith("." + result[-1]):
            result.append(domain)
    return set(result)

def main():
    if len(sys.argv) < 2:
        print("请提供输入文件路径作为参数")
        return

    file_name = sys.argv[1]
    print(f"🔍 正在以同步方式处理文件: {file_name}")

    # 1. 同步处理文件，提取所有域名
    domains = process_file_sync(file_name)

    if not domains:
        print("处理完成，未提取到有效域名。")
        return

    print(f"✅ 初步提取完成，有效规则数量: {len(domains)}")

    # 2. 移除子域名，保留父域名
    filtered_domains = remove_subdomains(domains)
    print(f"✂️ 去除子域名后剩余数量: {len(filtered_domains)}")

    # 3. 排序规则
    sorted_domains = sorted(filtered_domains)

    # 4. 写入文件
    try:
        with open(file_name, 'w', encoding='utf8') as f:
            # 写入结果：每一行是一个干净的域名（不带 '+.'），方便后续处理
            f.writelines(f"{domain}\n" for domain in sorted_domains) 
        print(f"💾 处理完成！已覆盖写入文件：{file_name}，最终规则数：{len(sorted_domains)}")
        print("💡 注意：输出结果是干净的域名（不含 '+.'），如果需要 Mihomo 格式，请记得手动添加前缀。")
    except Exception as e:
        print(f"❌ 写入文件时发生错误: {e}")

if __name__ == "__main__":
    main()
