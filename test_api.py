import requests
import json

response = requests.post(
    'http://192.168.1.168:5000/api/watch',
    json={
        'from': 'Cigli',
        'to': 'Konya',
        'date': '2026-01-18',
        'wagon_type': 'BUSINESS',
        'passengers': 1
    }
)
print(f"Status: {response.status_code}")
print(f"Response: {response.json()}")
