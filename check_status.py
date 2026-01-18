import requests
import time

for i in range(3):
    response = requests.get('http://192.168.1.168:5000/api/status')
    status = response.json()
    print(f"\nCheck {i+1}:")
    print(f"  Watching: {status.get('watching')}")
    print(f"  Wagon Not Found: {status.get('wagon_not_found')}")
    print(f"  Message: {status.get('message')}")
    time.sleep(5)
