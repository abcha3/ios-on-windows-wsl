# `/mnt/*` is 9P �?never compile there

---

## Symptom

Build "hangs". No errors, no progress, ever:

```bash
ps aux | grep swift-frontend
# many processes, each with ETIME 12:00 but CPU TIME 0:00
```

```bash
ps -eo pid,stat,wchan:24,args | grep ' D '
# ... D  p9_client_rpc  ...swift-frontend...
```

`D` = uninterruptible sleep, stuck in `p9_client_rpc`.

After 10�?2 minutes `.build` may hold only a few MB and zero `.o` files:

```bash
find .build -name '*.o' | wc -l      # 0
du -sh .build                        # 9.5M
```

---

## Cause

WSL accesses Windows drives through **9P** (`/mnt/c`, `/mnt/e`, �?. Every `open`/`read`/
`write` crosses the VM boundary. A Swift build touches tens of thousands of small files
(module cache, `.swiftinterface`, headers, `.d` files), so it degrades catastrophically.

Same build on ext4 (`/root`, `/tmp`): **~57 seconds**.

---

## Fix: build on a native path

Keep editing sources on Windows; **copy to Linux and build there**.

```bash
NATIVE=/root/$PROJECT
rsync -a --delete \
  --exclude '.build' --exclude '.bsp' --exclude 'xtool/.xtool-tmp' \
  /mnt/e/projects/YourApp/ios/ "$NATIVE/"
cd "$NATIVE" && swift build --swift-sdk darwin --triple arm64-apple-ios
```

Copy only the **final artifact** back:

```bash
cp -a "$NATIVE/xtool/Walk.app" /mnt/e/projects/YourApp/ios/dist/
```

### Watch out: `pkill -f` can kill your own script

```bash
pkill -f '/mnt/e/projects/YourApp/ios'      # �?also matches this script's own cmdline
```

The script's command line contains that string, so it commits suicide
(`[status: completed, exit code: 1]` with no output). Match on the *tool* instead:

```bash
pkill -f 'xtool dev build'
pkill -f 'swift-frontend -frontend'
```

### Check progress without triggering 9P

Any `ls`/`du` on `/mnt/*` is slow too. Query the native copy:

```bash
du -sh /root/project/.build
find /root/project/.build -name '*.o' | wc -l
```

---

## Which is slow, precisely

| Operation | /mnt/e | /root |
|---|---|---|
| `cp` 2 GB `.xip` | hours (streamed read) | 17 s |
| full Swift build | never completed | 57 s |
| incremental build | stalls | 14 s |

Anything with high file-count I/O must be native.
