import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: CaptureLibrary
    @State private var renamingItemID: CaptureItem.ID?
    @State private var renameDraft = ""

    var body: some View {
        List(selection: $library.selectedItemID) {
            Section("Captures") {
                ForEach(library.items) { item in
                    CaptureRow(
                        item: item,
                        isRenaming: renamingItemID == item.id,
                        renameDraft: $renameDraft,
                        onCommitRename: { commitRename(for: item) },
                        onCancelRename: cancelRename
                    )
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            library.selectedItemID = item.id
                        }
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            guard renamingItemID != item.id else { return }
                            model.open(item)
                        })
                        .contextMenu {
                            Button("Copy") {
                                model.copy(item)
                            }
                            if item.kind == .screenshot {
                                Button("Edit Snap") {
                                    library.selectedItemID = item.id
                                    model.edit(item)
                                }
                            }
                            Button("Rename") {
                                startRename(item)
                            }
                            Button("Reveal in Finder") {
                                library.selectedItemID = item.id
                                model.revealSelectedItem()
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                model.delete(item)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 240)
    }

    private func startRename(_ item: CaptureItem) {
        library.selectedItemID = item.id
        renameDraft = item.title
        renamingItemID = item.id
    }

    private func commitRename(for item: CaptureItem) {
        guard renamingItemID == item.id else { return }
        model.rename(item, to: renameDraft)
        renamingItemID = nil
        renameDraft = ""
    }

    private func cancelRename() {
        renamingItemID = nil
        renameDraft = ""
    }
}

private struct CaptureRow: View {
    @EnvironmentObject private var model: AppModel
    let item: CaptureItem
    let isRenaming: Bool
    @Binding var renameDraft: String
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    @FocusState private var isRenameFocused: Bool
    @State private var isCancellingRename = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(item.kind == .recording ? Color.red : Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Name", text: $renameDraft)
                        .font(QuickyTheme.roundedFont(size: 13, weight: .semibold))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor).opacity(0.92))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1)
                        }
                        .background(
                            RenameOutsideClickCommitView(
                                isActive: isRenaming,
                                onOutsideClick: {
                                    isCancellingRename = false
                                    onCommitRename()
                                }
                            )
                        )
                        .focused($isRenameFocused)
                        .onSubmit {
                            isCancellingRename = false
                            onCommitRename()
                        }
                        .onExitCommand {
                            isCancellingRename = true
                            onCancelRename()
                        }
                        .onAppear {
                            isCancellingRename = false
                            DispatchQueue.main.async {
                                isRenameFocused = true
                            }
                        }
                        .onChange(of: isRenameFocused) { isFocused in
                            guard !isFocused, isRenaming, !isCancellingRename else { return }
                            onCommitRename()
                        }
                } else {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(QuickyTheme.roundedFont(size: 13, weight: .semibold))
                            .lineLimit(1)

                        if model.copiedItemID == item.id {
                            Text("Copied to Clipboard")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .transition(.opacity.combined(with: .scale))
                        }
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        let size = "\(item.width)x\(item.height)"
        if let duration = item.duration {
            return "\(size) - \(DurationFormatter.short(duration))"
        }
        return "\(size) - \(DateFormatters.sidebarTime.string(from: item.createdAt))"
    }
}
