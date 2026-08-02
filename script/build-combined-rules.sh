#!/usr/bin/env python3
import asyncio
import os
import subprocess
import sys
from pathlib import Path
import aiohttp

# 1. 配置规则组
RULES = {
    "Ad": [
        "https://raw.githubusercontent.com/Cats-Team/dns-filter/main/abp.txt",
        "https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/AWAvenue-Ads-Rule.txt",
        "https://raw.githubusercontent.com/217heidai/adblockfilters/main/rules/adblockdnslite.txt",
        "https://gist.githubusercontent.com/qq6510/45173fd5128994bfbe0add665dec8b19/raw/xiaomi.txt",
    ],
    "AI": [
        "https://raw.githubusercontent.com/QuixoticHeart/rule-set/ruleset/meta/domain/ai.list",
        "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/github.list",
        "https://gist.githubusercontent.com/qq6510/c336dd2875fbf04fb50e1016783592d4/raw/Copilot.list",
    ]
}

# 2. 内存并发下载
async def fetch(session, url):
    try:
        async with session.get(url, timeout=aiohttp.ClientTimeout(total=30)) as response:
            if response.status == 200:
                return await response.text()
    except Exception as e:
        print(f"[WARN] 下载失败 {url}: {e}", file=sys.stderr)
    return ""

async def process_group(name, urls, semaphore, mihomo_bin):
    async with semaphore:
        print(f"[INFO] 开始处理规则组: {name}")
        async with aiohttp.ClientSession() as session:
            tasks = [fetch(session, url) for url in urls]
            results = await asyncio.gather(*tasks)

        # 在内存中合并与清洗
        domains = set()
        for content in results:
            for line in content.splitlines():
                line = line.strip()
                # 过滤空行、注释或无效规则
                if line and not line.startswith(('#', '!')):
                    # 处理 Mihomo 标准格式前缀 +.
                    if not line.startswith("+."):
                        line = f"+.{line}"
                    domains.add(line)

        txt_file = Path(f"{name}_Mihomo.txt")
        mrs_file = Path(f"{name}_Mihomo.mrs")

        # 写入内存清洗后的最终文本
        txt_file.write_text("\n".join(domains) + "\n", encoding="utf-8")

        # 调用 mihomo 编译 binary
        cmd = [mihomo_bin, "convert-ruleset", "domain", "text", str(txt_file), str(mrs_file)]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if res.returncode != 0:
            print(f"[ERROR] Mihomo 编译失败 ({name}): {res.stderr.decode()}", file=sys.stderr)
            return

        # 归档移动
        Path("../txt").mkdir(exist_ok=True)
        txt_file.rename(Path(f"../txt/{txt_file.name}"))
        mrs_file.rename(Path(f"../{mrs_file.name}"))
        print(f"[INFO] 规则组 {name} 处理完成")

async def main():
    mihomo_bin = "./mihomo"
    # 限制并发组数量，防止被 GitHub 封禁
    semaphore = asyncio.Semaphore(4)
    tasks = [process_group(name, urls, semaphore, mihomo_bin) for name, urls in RULES.items()]
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())
