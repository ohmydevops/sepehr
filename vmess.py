#!/usr/bin/python3

import random
import hashlib
import base64
import json
from pathlib import Path
import ipaddress

def config_generator(domain, uuid, operatorName, ws_path, ip=""):
    if ip == "":
        ip = domain
    # Generate random subdomain with letters and numbers
    random_subdomain = ''.join(random.choices('abcdefghijklmnopqrstuvwxyz0123456789', k=8))
    name = "🤍 sepehr - " + random_subdomain
    host = random_subdomain + "." + domain
    j = json.dumps({
        "v": "2", "ps": name, "add": ip, "port": "443", "id": uuid,
        "aid": "0", "net": "ws", "type": "none", "sni": host, "fp": "random",
        "host": host, "path": ws_path, "tls": "tls", "alpn": "h2,http/1.1"
    })
    return ("vmess://" + base64.b64encode(j.encode('ascii')).decode('ascii'))

# Read config from config.json
path = Path(__file__).parent
with open(str(path.joinpath('config.json')), 'r', encoding='utf-8') as f:
    config = json.load(f)

uuid = config['uuid']
ws_path = config['ws_path']
domain = config['domain']
port = 443

jsonObj = []

# Read cloudflare IP ranges and generate subscription
lines = open(str(path.joinpath('cloudflare_ips.txt')), 'r')
for line in lines:
    temp = []
    for tempIP in ipaddress.IPv4Network(str(line).strip()):
        temp.append(tempIP)
    finalIP = str(random.choice(temp))
    hash = (hashlib.md5(str(random.randint(10000, 3000000)).encode()).hexdigest())[0: 8]
    
    # Generate config with actual WebSocket path
    config = config_generator(domain, uuid, hash, ws_path, finalIP.strip())
    jsonObj.append(config)

fullRawconfigs = "\n".join(jsonObj)
print(base64.b64encode(fullRawconfigs.encode()).decode("utf-8", "ignore"))