#!/usr/bin/env python3
import sys
import urllib.request
import urllib.parse
import time
import json
import argparse
from datetime import datetime, timezone, timedelta

sys.stdout.reconfigure(line_buffering=True)

# 北京时间时区（UTC+8）
BEIJING_TZ = timezone(timedelta(hours=8), name='Asia/Shanghai')

def get_beijing_time():
    return datetime.now(BEIJING_TZ)

WEBSITES = [
    "http://scxy26.asia:9785/",
    "http://scxy26.asia:7979/",
    "http://scxy26.asia:6789/"
]

PUSH_URL = "https://api.day.app/D64zprNPpRypHArZ7ykAUT"

# 状态追踪
website_status = {}  # 当前状态
consecutive_failures = {}  # 连续失败次数
consecutive_successes = {}  # 连续成功次数
last_notification_time = {}  # 上次通知时间
NOTIFICATION_COOLDOWN = 300  # 5分钟冷却时间

def check_website(url, timeout=30, retries=2):
    """检查网站状态，带重试机制"""
    last_error = None
    for attempt in range(retries + 1):
        try:
            start_time = time.time()
            with urllib.request.urlopen(url, timeout=timeout) as response:
                elapsed_time = (time.time() - start_time) * 1000
                status_code = response.getcode()
                is_up = 200 <= status_code < 400
                return {
                    "url": url,
                    "status": "UP" if is_up else "DOWN",
                    "status_code": status_code,
                    "response_time": round(elapsed_time, 2),
                    "timestamp": get_beijing_time().strftime("%Y-%m-%d %H:%M:%S"),
                    "attempt": attempt + 1
                }
        except Exception as e:
            last_error = str(e)
            if attempt < retries:
                time.sleep(2)  # 重试间隔
    
    # 所有重试都失败
    return {
        "url": url,
        "status": "DOWN",
        "error": last_error,
        "timestamp": get_beijing_time().strftime("%Y-%m-%d %H:%M:%S"),
        "attempt": retries + 1
    }

def generate_report(results):
    report_lines = []
    report_lines.append(f"📊 网站状况报告 - {get_beijing_time().strftime('%Y-%m-%d %H:%M:%S')}\n")
    report_lines.append(f"共计监控 {len(results)} 个网站\n")
    report_lines.append("=" * 40 + "\n")

    up_count = sum(1 for r in results if r["status"] == "UP")
    down_count = len(results) - up_count

    report_lines.append(f"✅ 在线: {up_count} | ❌ 离线: {down_count}\n")
    report_lines.append("=" * 40 + "\n\n")

    for i, result in enumerate(results, 1):
        report_lines.append(f"{i}. {result['url']}\n")
        report_lines.append(f"   状态: {result['status']}\n")
        if result["status"] == "UP":
            report_lines.append(f"   响应码: {result['status_code']}\n")
            report_lines.append(f"   响应时间: {result['response_time']}ms\n")
        else:
            if "error" in result:
                report_lines.append(f"   错误: {result['error']}\n")
        report_lines.append("\n")

    return "".join(report_lines)

def generate_failure_report(failed_results):
    report_lines = []
    report_lines.append(f"🚨 网站故障通知 - {get_beijing_time().strftime('%Y-%m-%d %H:%M:%S')}\n")
    report_lines.append(f"共 {len(failed_results)} 个网站发生故障\n")
    report_lines.append("=" * 40 + "\n\n")

    for i, result in enumerate(failed_results, 1):
        report_lines.append(f"{i}. {result['url']}\n")
        report_lines.append(f"   故障时间: {result['timestamp']}\n")
        report_lines.append(f"   连续失败次数: {consecutive_failures.get(result['url'], 1)}\n")
        if "error" in result:
            report_lines.append(f"   错误信息: {result['error']}\n")
        report_lines.append("\n")

    return "".join(report_lines)

def generate_recovery_report(recovered_results):
    report_lines = []
    report_lines.append(f"✅ 网站恢复通知 - {get_beijing_time().strftime('%Y-%m-%d %H:%M:%S')}\n")
    report_lines.append(f"共 {len(recovered_results)} 个网站已恢复\n")
    report_lines.append("=" * 40 + "\n\n")

    for i, result in enumerate(recovered_results, 1):
        report_lines.append(f"{i}. {result['url']}\n")
        report_lines.append(f"   恢复时间: {result['timestamp']}\n")
        if result["status"] == "UP":
            report_lines.append(f"   响应码: {result['status_code']}\n")
            report_lines.append(f"   响应时间: {result['response_time']}ms\n")
        report_lines.append("\n")

    return "".join(report_lines)

def send_notification(title, content):
    try:
        data = {
            "title": title,
            "body": content
        }
        json_data = json.dumps(data).encode('utf-8')

        req = urllib.request.Request(
            PUSH_URL,
            data=json_data,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )

        with urllib.request.urlopen(req, timeout=30) as response:
            result = response.read().decode('utf-8')
            return True, result
    except Exception as e:
        return False, str(e)

def should_send_notification(url):
    """判断是否应该发送通知（去抖动）"""
    now = time.time()
    last_time = last_notification_time.get(url, 0)
    if now - last_time < NOTIFICATION_COOLDOWN:
        return False
    last_notification_time[url] = now
    return True

def check_all_websites():
    results = []
    for website in WEBSITES:
        result = check_website(website)
        results.append(result)
    return results

def main():
    parser = argparse.ArgumentParser(description='网站运行状况监控器')
    parser.add_argument('--report', action='store_true', help='生成报告并推送，然后退出')
    parser.add_argument('--no-push', action='store_true', help='不推送通知（仅与 --report 一起使用）')
    parser.add_argument('--monitor', action='store_true', help='持续监控模式，每60秒检测一次，故障时推送通知')
    args = parser.parse_args()

    if args.report:
        print("正在生成网站状况报告...")
        results = check_all_websites()
        report_content = generate_report(results)

        print(report_content)

        if not args.no_push:
            print("\n正在推送通知...")
            success, response = send_notification("每日网站状况报告", report_content)
            if success:
                print(f"✅ 推送成功: {response}")
            else:
                print(f"❌ 推送失败: {response}")
        return

    print("网站运行状况监控器")
    print("=" * 60)
    while True:
        print(f"\n[{get_beijing_time().strftime('%Y-%m-%d %H:%M:%S')}] 检查中...")
        print("-" * 60)

        has_failure = False
        newly_failed = []
        newly_recovered = []

        for website in WEBSITES:
            result = check_website(website)
            url = result["url"]
            current_status = result["status"]
            
            # 初始化计数器
            if url not in consecutive_failures:
                consecutive_failures[url] = 0
            if url not in consecutive_successes:
                consecutive_successes[url] = 0

            if current_status == "UP":
                print(f"✅ {url}")
                print(f"   状态: {result['status_code']} | 响应时间: {result['response_time']}ms")
                
                # 更新连续成功次数，重置失败计数
                consecutive_successes[url] += 1
                consecutive_failures[url] = 0
                
                # 检查是否从故障中恢复
                if url in website_status and website_status[url] == "DOWN":
                    if consecutive_successes[url] >= 2:  # 需要连续2次成功才算恢复
                        newly_recovered.append(result)
                        print(f"   ✅ {url} 已恢复上线 (连续{consecutive_successes[url]}次成功)")
            else:
                print(f"❌ {url}")
                print(f"   状态: {current_status}")
                if "error" in result:
                    print(f"   错误: {result['error']}")
                print(f"   尝试次数: {result.get('attempt', 1)}/{2 + 1}")  # 重试2次，共3次
                has_failure = True
                
                # 更新连续失败次数，重置成功计数
                consecutive_failures[url] += 1
                consecutive_successes[url] = 0
                
                # 检查是否是新故障
                if url not in website_status or website_status[url] != "DOWN":
                    if consecutive_failures[url] >= 2:  # 需要连续2次失败才算故障
                        newly_failed.append(result)
                        print(f"   ⚠️ 连续{consecutive_failures[url]}次失败，标记为故障")

            website_status[url] = current_status

        # 发送故障通知
        if newly_failed and should_send_notification("failure_batch"):
            failure_report = generate_failure_report(newly_failed)
            print(f"\n🚨 检测到{len(newly_failed)}个新故障网站，正在推送通知...")
            success, response = send_notification("网站故障通知", failure_report)
            if success:
                print(f"✅ 故障通知已推送: {response}")
            else:
                print(f"❌ 推送失败: {response}")

        # 发送恢复通知
        if newly_recovered and should_send_notification("recovery_batch"):
            recovery_report = generate_recovery_report(newly_recovered)
            print(f"\n✅ 检测到{len(newly_recovered)}个网站已恢复，正在推送通知...")
            success, response = send_notification("网站恢复通知", recovery_report)
            if success:
                print(f"✅ 恢复通知已推送: {response}")
            else:
                print(f"❌ 推送失败: {response}")

        if not has_failure:
            print("\n✅ 所有网站运行正常")

        print("\n等待60秒后再次检查... (按 Ctrl+C 退出)")
        try:
            time.sleep(60)
        except KeyboardInterrupt:
            print("\n监控已停止。")
            break

if __name__ == "__main__":
    main()
