import requests

session = requests.Session()

# 1. Get login page to retrieve CSRF token
print("1. Fetching root page for CSRF token...")
r1 = session.get("http://localhost:3001/")
csrf_token = ""
for line in r1.text.splitlines():
    if "csrf_token" in line and "value=" in line:
        parts = line.split('value="')
        if len(parts) > 1:
            csrf_token = parts[1].split('"')[0]
            break

print(f"   CSRF token: {csrf_token}")

# 2. POST login
print("2. Logging in...")
login_data = {
    "username": "admin",
    "password": "admin",
    "csrf_token": csrf_token
}
r2 = session.post("http://localhost:3001/login", data=login_data, allow_redirects=False)
token_cookie = r2.cookies.get('token')
print(f"   Status code: {r2.status_code}")
print(f"   Token Cookie: {token_cookie}")

headers = {
    "Cookie": f"token={token_cookie}; csrf_token={csrf_token}"
}

# 3. Get the home page to find a thumbnail link
print("3. Fetching gallery home page...")
r3 = session.get("http://localhost:3001/", headers=headers)
thumbnail_path = ""
for line in r3.text.splitlines():
    if "/thumbnails/" in line:
        parts = line.split('src="')
        if len(parts) > 1:
            thumbnail_path = parts[1].split('"')[0]
            break

if not thumbnail_path:
    print("   No thumbnail found in gallery!")
    print(r3.text[:1000])
    exit(1)

print(f"   Found thumbnail path: {thumbnail_path}")

# 4. Fetch the thumbnail first time (expecting 200 OK)
print("4. Fetching thumbnail first time...")
r4 = session.get(f"http://localhost:3001{thumbnail_path}", headers=headers)
print(f"   Status: {r4.status_code}")
print("   Response Headers:")
for k, v in r4.headers.items():
    print(f"      {k}: {v}")

etag = r4.headers.get("ETag") or r4.headers.get("etag")
print(f"   Etag: {etag}")

# 5. Fetch the thumbnail second time with If-None-Match (expecting 304 Not Modified)
if etag:
    print(f"5. Fetching thumbnail second time with If-None-Match: {etag}...")
    headers_with_etag = headers.copy()
    headers_with_etag["If-None-Match"] = etag
    r5 = session.get(f"http://localhost:3001{thumbnail_path}", headers=headers_with_etag)
    print(f"   Status: {r5.status_code}")
    print("   Response Headers:")
    for k, v in r5.headers.items():
        print(f"      {k}: {v}")

    # 6. Fetch with weak ETag prefix
    weak_etag = f"W/{etag}"
    print(f"6. Fetching thumbnail third time with weak If-None-Match: {weak_etag}...")
    headers_with_weak_etag = headers.copy()
    headers_with_weak_etag["If-None-Match"] = weak_etag
    r6 = session.get(f"http://localhost:3001{thumbnail_path}", headers=headers_with_weak_etag)
    print(f"   Status: {r6.status_code}")
