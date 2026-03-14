#!/usr/bin/python3

import random
import hashlib
import base64
import json
from pathlib import Path
import ipaddress
from urllib.parse import quote

def config_generator(domain, password, operatorName, xhttp_path, ip=""):
    if ip == "":
        ip = domain
    # Use domain directly without random subdomain for CloudFront
    name = "☁️ CloudFront - " + ip
    host = domain
    
    # Trojan link format: trojan://password@ip:port?params#name
    trojan_url = f"trojan://{password}@{ip}:443?security=tls&sni={host}&fp=random&type=httpupgrade&host={host}&path={quote(xhttp_path)}&alpn=h2,http/1.1#{quote(name)}"
    return trojan_url

# Read config from config.json
path = Path(__file__).parent
with open(str(path.joinpath('config.json')), 'r', encoding='utf-8') as f:
    config = json.load(f)

password = config['password']
xhttp_path = config['xhttp_path']
domain = config['domain']
port = 443

jsonObj = []

# Read CloudFront IP ranges and generate subscription
lines = open(str(path.joinpath('cloudfront_ips.txt')), 'r')
for line in lines:
    temp = []
    for tempIP in ipaddress.IPv4Network(str(line).strip()):
        temp.append(tempIP)
    finalIP = str(random.choice(temp))
    hash = (hashlib.md5(str(random.randint(10000, 3000000)).encode()).hexdigest())[0: 8]
    
    # Generate config with XHTTP path
    config = config_generator(domain, password, hash, xhttp_path, finalIP.strip())
    jsonObj.append(config)

fullRawconfigs = "\n".join(jsonObj)
print(base64.b64encode(fullRawconfigs.encode()).decode("utf-8", "ignore"))
