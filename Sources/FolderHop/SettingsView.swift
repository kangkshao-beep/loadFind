import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.system(size: 27)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("FolderHop · 設定").font(.system(size: 21, weight: .semibold))
                    Text("留返時間，做緊要嘅事。").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Form {
                Section("Finder 紀錄") {
                    Toggle("自動記低到訪嘅資料夾", isOn: Binding(
                        get: { state.preferences.trackingEnabled },
                        set: { state.setTracking?($0) }
                    ))
                    Text("\(state.trackingStatus.label)。只記低 Finder 前方視窗嘅資料夾路徑，唔會讀取檔案內容。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if state.trackingStatus == .denied {
                        Button("開啟自動化權限設定") { state.openAutomationSettings() }
                    }
                }
                Section("桌面小工具") {
                    Toggle("鎖定位置", isOn: $state.preferences.lockPosition)
                    Text("拖動橙色圖示可搬動面板；拖動其餘位置可 360° 翻轉。懸停唔會旋轉，移開後回正。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("將小工具搬返螢幕範圍內") { state.showDesktop?() }
                }
                Section("啟動") {
                    Toggle("登入時自動啟動", isOn: Binding(get: { state.loginEnabled }, set: { state.setLaunchAtLogin($0) }))
                }
                Section("忽略嘅資料夾") {
                    if state.history.excludedPaths.isEmpty {
                        Text("喺資料夾上按右鍵，就可以忽略佢同入面嘅子資料夾。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        ForEach(state.history.excludedPaths, id: \.self) { path in
                            HStack {
                                Text(state.displayPath(path)).font(.system(size: 11)).lineLimit(1).truncationMode(.middle).help(path)
                                Spacer()
                                Button("取消忽略") { state.removeExclusion(path) }.font(.system(size: 11))
                            }
                        }
                    }
                }
                Section("私隱") {
                    Label("所有紀錄只會儲存喺呢部 Mac，毋須帳戶或網絡。", systemImage: "lock.shield")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("清除到訪紀錄…", role: .destructive) { state.confirmClearHistory() }
                    Button("喺 Finder 顯示紀錄檔") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: AppDelegate.dataDirectory.path)
                    }
                }
            }.formStyle(.grouped)
            if let message = state.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(12).frame(maxWidth: .infinity).background(Palette.accent.opacity(0.08))
            }
            HStack {
                Text("FolderHop \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.5")")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Text("熟路，一撳就到。").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(width: 480, height: 690).tint(Palette.accent)
    }
}
