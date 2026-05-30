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

website_status = {}

def check_website(url, timeout=10):
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
                "timestamp": get_beijing_time().strftime("%Y-%m-%d %H:%M:%S")
            }
    except Exception as e:
        return {
            "url": url,
            "status": "DOWN",
            "error": str(e),
            "timestamp": get_beijing_time().strftime("%Y-%m-%d %H:%M:%S")
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
        if "error" in result:
            report_lines.append(f"   错误信息: {result['error']}\n")
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

def check_all_websites():
    results = []
    for website in WEBSITES:
        result = check_website(website)
        results.append(result)
    return results

def check_and_notify():
    results = check_all_websites()

    failed_websites = [r for r in results if r["status"] == "DOWN"]

    if failed_websites:
        failure_report = generate_failure_report(failed_websites)
        print("\n⚠️ 检测到故障网站，正在推送通知...")
        success, response = send_notification("网站故障通知", failure_report)
        if success:
            print(f"✅ 故障通知已推送: {response}")
        else:
            print(f"❌ 推送失败: {response}")
        return True
    return False

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
        for website in WEBSITES:
            result = check_website(website)
            if result["status"] == "UP":
                print(f"✅ {result['url']}")
                print(f"   状态: {result['status_code']} | 响应时间: {result['response_time']}ms")
                if website in website_status and website_status[website] == "DOWN":
                    print(f"   ✅ {website} 已恢复上线")
            else:
                print(f"❌ {result['url']}")
                print(f"   状态: {result['status']}")
                if "error" in result:
                    print(f"   错误: {result['error']}")
                has_failure = True

                if website not in website_status or website_status[website] != "DOWN":
                    failure_report = generate_failure_report([result])
                    print(f"\n🚨 检测到故障，正在推送通知...")
                    success, response = send_notification("网站故障通知", failure_report)
                    if success:
                        print(f"✅ 故障通知已推送: {response}")
                    else:
                        print(f"❌ 推送失败: {response}")

            website_status[website] = result["status"]

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
