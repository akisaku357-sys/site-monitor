import requests
import os

# 配置要监控的地址
TARGET_URL = "http://scxy26.asia:6780"
WEBHOOK_URL = os.environ.get('PA_WEBHOOK_URL')

def check_site():
    try:
        response = requests.get(TARGET_URL, timeout=10)
        if response.status_code == 200:
            print(f"站点正常: {TARGET_URL}")
        else:
            send_alert(f"站点异常，状态码: {response.status_code}")
    except Exception as e:
        send_alert(f"站点无法访问: {str(e)}")

def send_alert(message):
    if WEBHOOK_URL:
        payload = {"content": message}
        requests.post(WEBHOOK_URL, json=payload)
        print("告警已发送")
    else:
        print("未配置 Webhook URL")

if __name__ == "__main__":
    check_site()
