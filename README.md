# FolderHop

**熟路，一撳就到。** 原生 macOS 桌面資料夾捷徑，只展示 Finder 最近去過嘅 5 個資料夾。預設介面為繁體中文（香港），唔顯示到訪時間、次數或者分數。

本專案發佈於 [kangkshao-beep/loadFind](https://github.com/kangkshao-beep/loadFind)，採用 [MIT 許可](LICENSE)。參考專案嘅授權及聲明保留喺 `Resources/ThirdParty/`。

## 即刻使用

1. 開啟 `build/FolderHop.app`。可將佢拖入「應用程式」長期使用。
2. 喺面板撳「開啟自動紀錄」，允許 FolderHop 存取 **Finder 自動化**權限。
3. 正常用 Finder 開幾個資料夾；停留約一至兩秒，列表就會更新。
4. 撳任何資料夾，一步返到嗰個位置。

FolderHop 只保留桌面面板，唔會喺選單列或 Dock 放圖示，亦無獨立快捷面板。面板位於普通 App 視窗下面，顯示桌面時就會見到。按住左上角橙色圖示拖動，就可以搬動整個面板，毋須按 ⌥，拖拉邊緣可調整大小，位置同尺寸會儲存。右上角「⋯」可以開啟設定或結束 App。

面板只顯示最近 5 個不同嘅有效資料夾，無搜尋欄、常去排行或額外釘選區域。

## 外觀同設定

- 使用原生 `NSVisualEffectView` 做背景模糊，配合薄高光同玻璃邊緣，支援淺色／深色模式。磨砂玻璃會透出背景色彩，亦尊重 macOS「減少透明度」設定。
- 卡片有可見厚邊同獨立背面。喺橙色圖示以外嘅位置，**按住滑鼠左鍵拖動**先會旋轉，可以水平／垂直完整 360° 翻轉，亦可以連續拖動累積轉角。單純移動滑鼠或懸停唔會旋轉；放開左鍵停喺目前角度，滑鼠移出面板後平滑回到正面。開啟系統「減少動態效果」時會保持平面。
- 喺背面點一下，或用右鍵「翻返正面」，可以將卡片停返正面，方便開啟資料夾；再按住左鍵拖動可繼續旋轉。
- 「最近去過」固定最多 5 個；再次到訪會移到最前，已無效嘅路徑會略過。
- 懸停會顯示完整路徑。右鍵可以開啟、複製路徑、喺終端機開啟，或者忽略位置。
- 橙色圖示係移動把手，懸停時會顯示手形游標；移動位置同旋轉卡片係兩個獨立操作。
- 可以暫停自動紀錄、鎖定位置，同設定登入時自動啟動。登入項目建議先將 App 放入「應用程式」。如果搵唔到面板，重新開啟 FolderHop.app 會將佢搬返目前螢幕範圍內。
- 可以清除到訪紀錄；忽略清單會保留。忽略目錄亦包括佢入面嘅子資料夾。

## 權限同私隱

只需要 **系統設定 → 私隱與保安 → 自動化 → FolderHop → Finder**。拒絕後會停止追蹤，保留既有紀錄同開啟功能；重新允許後喺 App 撳「重試」。毋須輔助使用、輸入監控或完整磁碟存取權限。

FolderHop 無帳戶、無伺服器、無雲端同步、無分析追蹤、無外部 API。唔會掃描磁碟、讀取檔案內容，亦唔會將檔案修改當成到訪。路徑唔會無條件輸出到應用程式日誌。

資料儲存喺：

```text
~/Library/Application Support/FolderHop/history.json
```

採用原子寫入，資料夾權限 0700、紀錄檔權限 0600。損壞嘅紀錄會先另存備份，成功保留後先重新開始；備份失敗時唔會覆寫原檔。視窗位置由 macOS 儲存喺應用程式偏好設定。

## 建構同測試

最低 macOS **14.0**，需要 Xcode 15／Swift 5.9 或更新版本。唔需要第三方套件或網絡下載依賴。

### Xcode

開啟 `FolderHop.xcodeproj`，選擇 **FolderHop** scheme 同 **My Mac**，按 Run。工程包含 App、靜態 FolderCore framework，同核心單元測試 target；可以直接用 Product → Test。

```sh
xcodebuild -project FolderHop.xcodeproj -scheme FolderHop \
  -configuration Debug -derivedDataPath .build/xcode \
  -destination 'platform=macOS' build
```

### 命令列

先結束正在執行嘅 FolderHop，再執行：

```sh
./scripts/test.sh
./scripts/build-app.sh
open build/FolderHop.app
```

`build-app.sh` 會以 Release 建構、加入原生圖示同權限描述，並作本機 ad-hoc 簽署同驗證。輸出係目前 Mac 架構；今次交付係 **Apple Silicon（arm64）**。Intel Mac 可以用同一份源碼喺當機重新建構。重新建構後，macOS 可能要求重新授予自動化權限。

呢個本機開發版未經 Developer ID 公證。其他 Mac 如攔截開啟，可用 Finder 右鍵「開啟」，或喺「私隱與保安」允許；正式分發應改用 Developer ID 簽署同公證。

Swift Package 同 Xcode 工程共用完全相同源碼。新增 Swift 檔案後可執行 `python3 scripts/generate-xcode-project.py` 更新工程，毋須安裝 XcodeGen。建構快取全部放喺 `.build/`。

## 技術架構

| 模組 | 職責 |
| --- | --- |
| `FolderCore/FolderHistory.swift` | 真實到訪事件、最近排序、窗口／路徑去重、忽略清單；保留舊版資料相容性 |
| `FolderCore/Persistence.swift` | 本地 JSON 原子儲存、讀取驗證、損壞備份、設定 |
| `FolderHop/FinderTracker.swift` | NSWorkspace 激活通知、Finder Apple Events、自動化授權、前台輪詢 |
| `FolderHop/AppState.swift` | 共用最近五項資料來源、有效目錄過濾、開啟資料夾同錯誤處理 |
| `FolderHop/AppDelegate.swift` | 桌面層窗口、Logo 投影命中與移動、Spaces、尺寸／位置還原 |
| `FolderHop/FolderBoardView.swift` | 磨砂玻璃正面／背面、左鍵拖動手勢、完整翻轉同回正 |
| `FolderCore/PanelTilt.swift` | 由拖動位移累積轉角、零尺寸同無效資料保護 |
| `FolderCore/CardGeometry.swift` | 有厚度卡片嘅三維旋轉、透視投影、正背面剔除同邊界適配 |
| `FolderHop/SolidCardView.swift` | 玻璃正面、品牌背面、圓角實體側壁、金屬邊緣光照 |
| `FolderHop/SettingsView.swift` | 設定、權限狀態、登入項目、清除紀錄 |

Finder 前台時每 1.5 秒讀取前方窗口 **ID 同 target 目錄**；激活 Finder 即時檢查。離開 Finder 或暫停紀錄時停止定時器。同窗口同路徑停留只記一次；A → B → A 或切換窗口可新增到訪。從 FolderHop 開啟後嘅下一次 Finder 檢查會去重。授權／健康檢查本身唔會將背景 Finder 位置計成到訪。

桌面窗口位於 `desktopIconWindow + 1`，可以喺不同 Spaces 顯示；普通 App 視窗自然蓋過佢。滑鼠翻轉只追蹤本窗口嘅事件，唔用全域監聽或輪詢，毋須額外權限。切換顯示器時會將離開可見範圍嘅窗口搬返螢幕內。

## 驗證、參考與限制

見 [驗證紀錄](docs/VALIDATION.md) 及 [參考項目審查](docs/REFERENCE_REVIEW.md)。

- 只能紀錄**啟用之後**觀察到嘅 Finder 到訪，無法還原 macOS 過去完整使用紀錄。
- Finder 無公開逐次目錄切換通知。採用前台通知加低頻檢查；少於 1.5 秒嘅快速跳轉可能漏記，唔會聲稱監控到全部導航。長時間使用多個不同 Finder tab，係以當前前方 tab 嘅 target 為準。
- 最近項目、搜尋、AirDrop 等虛擬位置唔係實際資料夾，會略過；無窗口時唔新增事件。
- 已刪除、搬走或未連接磁碟嘅路徑，喺列表重新計算時隱藏；點擊前亦會再次驗證，唔會崩潰。MVP 未用 bookmark 跟隨目錄改名或搬位；喺 Finder 前往新位置後便會重新紀錄。
- 系統設定、Stage Manager、全螢幕 App 或「顯示桌面」動畫可能影響桌面窗口可見性；可以顯示桌面，或重新開啟 App／喺設定恢復位置。
- 已喺本機 macOS 26 驗證；macOS 14／15、多實體螢幕、登入自動啟動仍需更多實機測試。

後續可以加入簽署與公證、目錄 bookmark、多顯示器位置分別記憶，並改善快速導航嘅捕捉。MVP 保持無網絡、無額外權限同無第三方依賴。
