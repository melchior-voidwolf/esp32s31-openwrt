#!/usr/bin/env python3
"""Benchmark authenticated LuCI pages without exposing credentials or session IDs."""

import http.client
import http.cookies
import html
import json
import math
import os
import re
import statistics
import time
import urllib.parse

HOST = os.environ.get("S31_HOST", "10.0.0.84")
BASE = "/cgi-bin/luci"
USERNAME = os.environ.get("LUCI_USERNAME", "root")
PASSWORD = os.environ.get("LUCI_PASSWORD", "")
RESULTS = os.environ.get("LUCI_RESULTS", "/tmp/luci-auth-results.json")
if not PASSWORD:
    raise SystemExit("set LUCI_PASSWORD before running this benchmark")


def request(method, path, body=None, headers=None, timeout=25):
    started = time.perf_counter()
    connection = http.client.HTTPConnection(HOST, 80, timeout=timeout)
    connection.request(method, path, body=body, headers=headers or {})
    response = connection.getresponse()
    headers_done = time.perf_counter()
    payload = response.read()
    finished = time.perf_counter()
    result = {
        "status": response.status,
        "headers": {key.lower(): value for key, value in response.getheaders()},
        "body": payload,
        "starttransfer": headers_done - started,
        "total": finished - started,
    }
    connection.close()
    return result


def login():
    body = urllib.parse.urlencode({
        "luci_username": USERNAME,
        "luci_password": PASSWORD,
    })
    response = request("POST", BASE + "/", body=body, headers={
        "Content-Type": "application/x-www-form-urlencoded",
        "Content-Length": str(len(body)),
        "Connection": "close",
    })
    print(
        f"login POST: HTTP {response['status']} "
        f"start={response['starttransfer']:.3f}s total={response['total']:.3f}s"
    )
    cookie = http.cookies.SimpleCookie()
    cookie.load(response["headers"].get("set-cookie", ""))
    print(f"login redirect: {response['headers'].get('location', '?')}")
    if "sysauth_http" not in cookie:
        print("response header names:", ", ".join(sorted(response["headers"])))
    if "sysauth_http" not in cookie:
        raise RuntimeError("login did not return sysauth_http; check credentials/status")
    if response["status"] not in (301, 302, 303):
        raise RuntimeError(f"unexpected login status {response['status']}")
    return cookie["sysauth_http"].value


def logout(session):
    response = request("GET", BASE + "/admin/logout", headers={
        "Cookie": f"sysauth_http={session}",
        "Connection": "close",
    }, timeout=10)
    print(f"session destroyed: {'yes' if response['status'] in (301, 302, 303) else 'unconfirmed'}")


def benchmark(name, path, session, count, save_path=None):
    rows = []
    for index in range(1, count + 1):
        response = request("GET", path, headers={
            "Cookie": f"sysauth_http={session}",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Connection": "close",
        })
        body = response["body"]
        login_required = response["headers"].get("x-luci-login-required") == "yes"
        if login_required or b'name="luci_password"' in body:
            raise RuntimeError(f"{name} returned the login page instead of authenticated content")
        title_match = re.search(br"<title>(.*?)</title>", body, re.I | re.S)
        title = html.unescape(title_match.group(1).decode("utf-8", "replace")).strip() if title_match else "?"
        print(
            f"{name} req{index}: HTTP {response['status']} size={len(body)}B "
            f"start={response['starttransfer']:.3f}s total={response['total']:.3f}s"
        )
        if index == 1:
            print(f"{name} title: {title}")
            if save_path:
                with open(save_path, "wb") as stream:
                    stream.write(body)
        if response["status"] != 200:
            raise RuntimeError(f"{name} returned HTTP {response['status']}")
        rows.append({
            "request": index,
            "status": response["status"],
            "bytes": len(body),
            "starttransfer": response["starttransfer"],
            "total": response["total"],
        })
    times = sorted(row["total"] for row in rows)
    p95 = times[math.ceil(len(times) * 0.95) - 1]
    print(
        f"{name} summary: min={times[0]:.3f}s p50={statistics.median(times):.3f}s "
        f"p95={p95:.3f}s max={times[-1]:.3f}s"
    )
    return rows


def main():
    results = {}
    session = login()
    try:
        results["overview"] = benchmark(
            "overview", BASE + "/admin/status/overview", session,
            int(os.environ.get("LUCI_OVERVIEW_COUNT", "20")),
            "/tmp/luci-authenticated-overview.html",
        )
        results["network"] = benchmark(
            "network", BASE + "/admin/network/network", session,
            int(os.environ.get("LUCI_NETWORK_COUNT", "6")),
            "/tmp/luci-authenticated-network.html",
        )
    finally:
        logout(session)
    with open(RESULTS, "w") as stream:
        json.dump(results, stream, indent=2)
    print(f"results: {RESULTS}")


if __name__ == "__main__":
    main()
