# ios-on-windows-wsl

**鍦?Windows 涓婃瀯寤恒€佺鍚嶅苟瀹夎 iOS App 鈥斺€?涓嶉渶瑕?Mac銆?*

An agent skill (and runnable toolkit) for building, signing, and installing iOS apps on Windows via WSL, with no Mac involved.

> 绔埌绔獙璇侊細Kotlin Multiplatform + SwiftUI 搴旂敤缂栬瘧銆佺敤鍏嶈垂 Apple ID 绛惧悕銆佸畨瑁呭埌 iPhone 12锛坕OS 27.0.1锛夛紝骞舵垚鍔熻繍琛屻€?
---

## 瀹冭В鍐充粈涔堥棶棰?
Windows 涓婃病鏈?Xcode锛屼紶缁熶笂鍋氫笉浜?iOS銆傝繖涓?skill 鎶娿€屾€庝箞缁曡繃鍘汇€嶇殑瀹屾暣鐭ヨ瘑娌夋穩涓嬫潵鈥斺€?*灏ゅ叾鏄偅浜涘彧鏈夌湡姝ｈ窇涓€閬嶆墠浼氬彂鐜般€佷笖鎶ラ敊淇℃伅鎸囧悜瀹屽叏閿欒鏂瑰悜鐨勫湴鏂?*銆?
鍏鍏抽敭鍏冲崱锛?
| # | 鍏冲崱 | 閿欏湪鍝細鎬庢牱 |
|---|---|---|
| 1 | Swift 蹇呴』 鈮?6.4.1 | 鎶ャ€孲DK 缂?arm64 鏍囧噯搴撱€嶏紝瀹為檯鏄紪璇戝櫒澶棫 |
| 2 | KMP expect/actual 闇€灞曞钩 | 涓ょ鏄捐€屾槗瑙佺殑鍐欐硶閮戒細澶辫触 |
| 3 | 澶存枃浠跺繀椤讳粠婧愮爜缂?| 鐢?klib 褰撲緷璧栵紝浣犺嚜宸辩殑绫诲瀷涓€涓兘涓嶅鍑?|
| 4 | `ld64.lld` 娌℃湁 `-r` | SwiftPM 鐨?library target 蹇呯劧鍗′綇 |
| 5 | 骞冲彴閲嶅娉ㄥ唽 | SDK 閲屾湁涓や唤 Developer 鏍戯紝鏋勫缓绯荤粺鎷掔粷鍚姩 |
| 6 | `/mnt/*` 鏄?9P | 缂栬瘧杩涚▼鍏ㄥ牭鍦?`p9_client_rpc`锛?0 鍒嗛挓浜т笉鍑轰竴涓?`.o` |
| 7 | `github.com` 琚樆鏂?| SDK 鐗堟湰妫€鏌ヨ秴鏃?鈫?璇垽杩囨湡 鈫?閲嶅缓 鈫?瑕嗙洊浣犵殑淇 |
| 8 | **USB/IP 瑁呬笉浜?App** | 绛惧ソ浜嗐€佸寘涔熸墦濂斤紝鍗″湪鏈€鍚庝竴姝ワ紝鎶ラ敊鎸囧悜銆屽ぇ鏂囦欢銆嶄絾鍏跺疄鏄€氶亾鏍规湰涓嶉€?|

绗?8 鏉℃槸鑺辨椂闂存渶澶氥€佷篃鏈€鍙嶇洿瑙夌殑涓€鏉°€傝瑙?`references/relay-install.md`銆?
---

## 瀹夎鍒颁綘鐨?agent

```bash
git clone https://github.com/abcha3/ios-on-windows-wsl.git \
  ~/.agents/skills/ios-on-windows-wsl
```

锛圖SH / Claude Code 绛夋敮鎸?`~/.agents/skills/` 绾﹀畾鐨勫鎴风浼氳嚜鍔ㄥ姞杞姐€傦級

瑙﹀彂璇嶏細`iOS on Windows`銆乣no Mac`銆乣WSL iOS`銆乣install to iPhone from Windows`锛屾垨鎾炰笂杩欎簺鎶ラ敊锛歚Mux error -8`銆乣AFC Write error: 30`銆乣platform already registered`銆乣Darwin SDK is out of date`銆乣-r is not yet implemented`銆?
---

## 鐩存帴褰撹剼鏈敤

涓嶄緷璧?agent锛岃剼鏈彲浠ュ崟鐙窇锛?
```bash
# 涓€娆℃€х幆澧冿紙WSL 鍐咃級
bash scripts/setup-toolchain.sh        # Swift 6.4.1 / Darwin SDK / ld trampoline
bash scripts/sdk-layout.sh             # 娑堥櫎骞冲彴閲嶅娉ㄥ唽
bash scripts/build-xcframework.sh      # KMP -> XCFramework

# 鏋勫缓 + 绛惧悕
bash scripts/build-native.sh           # 鍦ㄥ師鐢熺洏鏋勫缓锛堥伩寮€ 9P锛?bash scripts/sign-and-package.sh       # -> .ipa
```

```powershell
# 瑁呮満锛圵indows 渚э級
powershell -File scripts\relay-setup.ps1       # 寤?TCP 妗ワ紙绔彛 27016锛?powershell -File scripts\relay-handoff.ps1     # 鎶婅澶囦氦鍥?Windows
```

```bash
bash scripts/install-app.sh app.ipa
```

> Apple ID 鐧诲綍鏄氦浜掑紡鐨勶紝蹇呴』鐢变汉浜茶嚜杈撳叆銆傜敤 `scripts/login-apple.cmd` 寮€涓€涓帶鍒跺彴绐楀彛銆?
---

## 鐩綍

```
SKILL.md                      涓绘枃妗ｏ細绠＄嚎銆佸叓閬撳叧鍗°€佷笉鍙繚鍙嶇殑瑙勫垯
references/
  troubleshooting.md          鎶ラ敊鏂囨湰 鈫?鍘熷洜 鈫?淇锛堝崱浣忔椂浠庤繖閲屾煡锛?  relay-install.md            鈽?USB/IP 涓轰粈涔堜笉琛?+ Apple 椹卞姩涓户
  kmp-framework.md            KMP 鈫?XCFramework 鍏ㄦ祦绋嬩笌浜掓搷浣滃潙
  ld-trampoline.md            -r 鏇夸唬瀹炵幇 + dependency_info 浜岃繘鍒舵牸寮?  toolchain.md                Swift 6.4.1銆丏arwin SDK 瀹夎
  sdk-layout.md               骞冲彴閲嶅娉ㄥ唽锛屼綍鏃跺彲瀹夊叏闅愯棌
  build-native.md             9P 缂栬瘧鍗℃锛屾敼鍦?ext4 鏋勫缓
  network.md                  github.com 闃绘柇涓?SDK 璇垽
scripts/                      11 涓彲杩愯鑴氭湰
```

---

## 杈圭晫

**宸茶鐩?*锛歐indows + WSL 涓婄殑 iOS 鏋勫缓銆佺鍚嶃€佺湡鏈哄畨瑁呫€?
**涓嶈鐩?*锛?- App Store 涓婃灦锛堥渶瑕佷粯璐瑰紑鍙戣€呰鍒掞紝閮ㄥ垎姝ラ浠嶉渶 Mac锛?- iOS 妯℃嫙鍣紙闇€瑕?macOS锛?- 鍚庡彴鎵ц楠岃瘉鈥斺€旀瘮濡傘€岄攣灞?8 灏忔椂 GPS 鏄惁杩炵画銆嶏紝鍙兘闈犱汉鐪熺殑甯︾潃鎵嬫満璧颁竴瓒燂紝**鏋勫缓鎴愬姛涓嶄唬琛ㄨ兘鐢?*

---

## 璇存槑

杩欎簺鍐呭鏉ヨ嚜涓€娆＄湡瀹炵殑绉绘椤圭洰銆傝俯杩囩殑姣忎釜鍧戦兘璁颁笅浜嗐€屼负浠€涔堜細杩欐牱銆嶏紝鑰屼笉鍙槸銆屾€庝箞鍋氥€嶁€斺€斿洜涓轰笅娆″伐鍏烽摼鍗囩骇鏃讹紝鍧忔帀鐨勪竴瀹氭槸閭ｄ簺鍘熷洜锛岃€屼笉鏄楠ゃ€?
娆㈣繋鎻?issue / PR 琛ュ厖浣犲湪鍒殑鐜閲岄亣鍒扮殑鎯呭喌銆?
## License

MIT
