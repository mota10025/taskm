import SwiftUI

struct CategorySettingsView: View {
    let viewModel: KanbanViewModel
    @State private var newName = ""
    @State private var newColor = Color(hex: 0x8a8a8a)
    @State private var newTextColor = Color(hex: 0x2a2a2a)
    @State private var editingColors: [String: Color] = [:]
    @State private var editingTextColors: [String: Color] = [:]
    @State private var editingNames: [String: String] = [:]
    @State private var deleteTarget: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // ヘッダー
                HStack {
                    Text("カテゴリ管理")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                // カテゴリ一覧
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.categories) { category in
                            categoryRow(category)
                            Divider().background(Color.white.opacity(0.05))
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Divider().background(Color.white.opacity(0.1))

                // 新規追加行
                HStack(spacing: 8) {
                    TextField("カテゴリ名", text: $newName)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                        .foregroundColor(.white)
                        .onSubmit { addCategory() }

                    VStack(spacing: 2) {
                        Text("背景")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                        ColorPicker("", selection: $newColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 30)
                    }

                    VStack(spacing: 2) {
                        Text("文字")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                        ColorPicker("", selection: $newTextColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 30)
                    }

                    Button("追加") { addCategory() }
                        .buttonStyle(.borderedProminent)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16)
            }
        }
        .onAppear { initEditingState() }
        .alert("カテゴリを削除", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("削除", role: .destructive) {
                if let name = deleteTarget {
                    performDelete(name)
                }
            }
            Button("キャンセル", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("カテゴリ「\(deleteTarget ?? "")」を削除しますか？")
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: CategoryItem) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Text("背景")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { editingColors[category.name] ?? Color(hexString: category.color) },
                        set: { color in
                            editingColors[category.name] = color
                            updateColor(category.name, color: color)
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 30)
            }

            VStack(spacing: 2) {
                Text("文字")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { editingTextColors[category.name] ?? Color(hexString: category.textColor) },
                        set: { color in
                            editingTextColors[category.name] = color
                            updateTextColor(category.name, color: color)
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 30)
            }

            // プレビュー
            Text("Aa")
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(editingColors[category.name] ?? Color(hexString: category.color))
                .foregroundColor(editingTextColors[category.name] ?? Color(hexString: category.textColor))
                .cornerRadius(4)

            TextField("カテゴリ名", text: Binding(
                get: { editingNames[category.name] ?? category.name },
                set: { editingNames[category.name] = $0 }
            ), onCommit: {
                let newName = editingNames[category.name]?.trimmingCharacters(in: .whitespaces) ?? ""
                if !newName.isEmpty && newName != category.name {
                    performRename(category.name, to: newName)
                }
            })
            .textFieldStyle(.plain)
            .padding(6)
            .background(Color.white.opacity(0.05))
            .cornerRadius(4)
            .foregroundColor(.white)

            Button(action: { deleteTarget = category.name }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private func initEditingState() {
        for cat in viewModel.categories {
            editingColors[cat.name] = Color(hexString: cat.color)
            editingTextColors[cat.name] = Color(hexString: cat.textColor)
            editingNames[cat.name] = cat.name
        }
    }

    private func addCategory() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let colorHex = newColor.toHexString()
        let textColorHex = newTextColor.toHexString()
        let db = DatabaseManager.shared
        Task {
            do {
                try await db.createCategory(name: name, color: colorHex, textColor: textColorHex)
                viewModel.loadTasks()
                newName = ""
                newColor = Color(hex: 0x8a8a8a)
                newTextColor = Color(hex: 0x2a2a2a)
                try? await Task.sleep(for: .milliseconds(300))
                initEditingState()
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func updateColor(_ name: String, color: Color) {
        let hex = color.toHexString()
        let db = DatabaseManager.shared
        Task {
            do {
                try await db.updateCategory(oldName: name, newColor: hex)
                viewModel.loadTasks()
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func updateTextColor(_ name: String, color: Color) {
        let hex = color.toHexString()
        let db = DatabaseManager.shared
        Task {
            do {
                try await db.updateCategory(oldName: name, newTextColor: hex)
                viewModel.loadTasks()
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func performRename(_ oldName: String, to newName: String) {
        let db = DatabaseManager.shared
        Task {
            do {
                try await db.updateCategory(oldName: oldName, newName: newName)
                viewModel.loadTasks()
                try? await Task.sleep(for: .milliseconds(300))
                initEditingState()
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func performDelete(_ name: String) {
        let db = DatabaseManager.shared
        Task {
            do {
                try await db.deleteCategory(name: name)
                viewModel.loadTasks()
                try? await Task.sleep(for: .milliseconds(300))
                initEditingState()
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

// Color → hex文字列変換
extension Color {
    func toHexString() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components,
              components.count >= 3 else {
            return "#8a8a8a"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
