# Network: `github.com` blocking breaks SDK checks

---

## Symptom

```
Error: HTTPClientError.deadlineExceeded
Darwin SDK is out of date. Rebuilding...
```

then either a huge download or a hard failure. Also:

```
Error: StreamClosed(streamID: HTTP2StreamID(1), errorCode: HTTP2ErrorCode<0x8 Cancel>)
```

Note the misleading first line: the SDK is **fine**. The version check timed out, and
xtool concluded "out of date".

---

## Diagnosis

```bash
for u in https://github.com https://api.github.com https://download.swift.org; do
  printf "%-32s " "$u"
  curl -s -m 12 -o /dev/null -w 'HTTP=%{http_code} t=%{time_total}s\n' "$u" || echo FAIL
done
```

Typical in CN:

```
https://github.com          HTTP=000 t=12.0s   ← blocked
https://api.github.com      HTTP=200 t=0.36s   ← fine
https://download.swift.org  HTTP=302 t=0.47s
```

`api.github.com` working while `github.com` times out is the giveaway. Confirm at the TCP
level:

```bash
getent hosts github.com          # often 20.205.243.166 (blocked)
timeout 6 curl -v -o /dev/null https://github.com 2>&1 | grep -E 'Trying|Connected'
# * Trying 20.205.243.166:443...   (then nothing)
```

---

## Fix: pin a reachable edge IP

Probe several GitHub edges (a CDN — different IPs route differently):

```bash
for ip in 140.82.112.3 140.82.113.3 140.82.114.3 20.27.177.113 20.205.243.166; do
  printf "%-16s " "$ip"
  curl -s -m 6 --resolve "github.com:443:$ip" -o /dev/null -w 'HTTP=%{http_code} t=%{time_total}s\n' https://github.com
done
```

Observed:

```
140.82.112.3     HTTP=200 t=6.0s
140.82.113.3     HTTP=200 t=6.0s
140.82.114.3     HTTP=200 t=2.0s
20.27.177.113    HTTP=200 t=0.53s   ← chosen
20.205.243.166   HTTP=000 timeout   ← what DNS returns
```

Persist it:

```bash
sudo cp /etc/hosts /etc/hosts.before-github-fix
IP=20.27.177.113
sudo sed -i '/walk-ios: github/d' /etc/hosts
echo "$IP github.com # walk-ios: github 可达性修复" | sudo tee -a /etc/hosts
```

Verify **without** `--resolve` (system resolution must now be fast):

```bash
curl -s -m 15 -o /dev/null -w '%{http_code} %{time_total}s\n' https://github.com
# 200 0.45s
```

IPs change over time — re-probe rather than copying this value verbatim.

---

## Alternative: use a proxy

If the host runs a proxy (e.g. Clash on `127.0.0.1:7890`), WSL usually **cannot** reach
it via `127.0.0.1` (separate network namespace) and often not via the host IP either
unless the proxy listens on `0.0.0.0` and the firewall allows it. Test:

```bash
HOSTIP=$(ip route show default | awk '{print $3}' | head -1)
curl -s -m 6 -x "http://$HOSTIP:7890" -o /dev/null -w '%{http_code}\n' https://github.com
```

If that returns `000`, fall back to the `/etc/hosts` method.

---

## Why this blocks *building*, not just downloading

`xtool dev build` performs an SDK freshness check on every invocation. A timed-out check
is treated as "stale", which triggers a **reinstall**. That reinstall:

- overwrites `toolset/bin/ld64.lld` (kills the `-r` trampoline),
- restores the `Platforms` directory you may have hidden,
- and itself needs the network.

So a blocked `github.com` can undo every local fix in one command. **Fix network first.**

---

## Caches that make it worse

```bash
find ~/.cache/xtool -type f     # normally just pid-*.lock
```

There is no documented offline mode; `skipSetup` only affects project creation. Do not
expect a "don't check" flag to exist.
