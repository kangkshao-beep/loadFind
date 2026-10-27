# 參考項目審查

目前版本已依照最新需求改為純桌面 3D 面板，移除選單列圖示、獨立快捷面板及全域快捷鍵。以下保留原始技術調研紀錄，唔代表全部參考功能仍然提供。

審查日期：2026-10-26。FolderHop 係獨立實作，無直接引入兩個專案嘅套件、圖片或品牌資產。完整閱讀咗以下實作，同時核對原始授權檔。保留授權副本喺 `Resources/ThirdParty/`，並隨 `.app` 打包。

## Haunts

- 專案：[rhydlewis/haunts](https://github.com/rhydlewis/haunts)
- 審查時 main：`f673d2dd22151667ebef6573c3493b053f5ec923`
- 讀取檔案：`README.md`、`app/Sources/HauntsCore/FinderTracker.swift`、`app/Sources/zforfinder/HotKey.swift`、`LICENSE`。
- 授權：MIT，Copyright © 2026 Rhyd Lewis；許可副本見 `Resources/ThirdParty/Haunts-MIT.txt`。

實作使用 NSAppleScript 讀取 Finder **front window target**，約兩秒輪詢，同路徑唔重複紀錄。NSAppleScript 依照該專案實測經驗留喺主執行緒；唔使用 Finder selection 或 insertion location，避免將選取嘅子目錄誤當成實際到訪。全域快捷鍵用 Carbon RegisterEventHotKey，毋須輸入監控權限。

FolderHop 採納上述技術路線，加入前台激活通知、窗口 ID、無窗口處理、離開 Finder 即停止輪詢、短查詢 timeout，以及非同步自動化權限預檢。設定啟用後先要求授權，啟動時唔會無故再次彈出權限請求。

Haunts 嘅多來源暖啟動會讀取 git、shell、編輯器等訊號。FolderHop 無引入呢類來源，確保「最常去」只反映實際記低嘅到訪。亦唔直接採用衰減加權分數：按本專案要求，近 30 天**真實頻率為第一排序鍵、最近到訪為第二排序鍵**。唔會用人造範例或預設常用目錄冒充使用者歷史。

## TileTop

- 專案：[NeutrinoLiu/TileTop](https://github.com/NeutrinoLiu/TileTop)
- 審查時 main：`63ae118d711e8f7fc0eaa510678e996794f2456e`
- 讀取檔案：`README.md`、`Sources/WidgetCore.swift`（窗口、玻璃背景、拖動、位置保存與多顯示器處理）、`LICENSE`、`NOTICE`。
- 授權：Apache License 2.0，Copyright 2026 NeutrinoLiu；許可與 NOTICE 副本見 `Resources/ThirdParty/`。

實作使用真正嘅 AppKit borderless／resizable NSWindow，level 設為 `CGWindowLevelForKey(.desktopIconWindow) + 1`，配合 `canJoinAllSpaces`、`stationary`、`ignoresCycle`。NSVisualEffectView 提供毛玻璃，窗口可變 key 接受輸入；拖動用 `performDrag`，位置由 macOS 或設定儲存。TileTop 另外有每顯示器 UUID 記憶、WebKit 窗口同完整檔案操作。

FolderHop 用獨立 SwiftUI 介面與 AppKit 窗口承載；採用相同公開系統 API 做桌面層級、拖動與背景模糊。無引入 TileTop 嘅 WebKit、檔案管理器、複製刪除功能或資產。多螢幕 MVP 先提供可見範圍校正，未複製其完整 UUID 位置系統。

## 授權與分發

兩個專案並無喺本工程內連結或作為執行依賴。FolderHop 源碼獨立編寫，保留上述實作參考及授權資料，方便追溯。若未來直接移植實質源碼，需繼續保留相關作者標示、MIT 許可，及 Apache 2.0 嘅許可、NOTICE 與修改說明。

App 目前以本機開發方式簽署，未經 Developer ID 公證，亦無上架或設定雲端服務。
