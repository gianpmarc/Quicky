import Foundation

enum CaptureLibraryError: LocalizedError {
    case missingFile(String)
    case unableToRename(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let fileName):
            return "The original file '\(fileName)' could not be found."
        case .unableToRename(let fileName):
            return "The capture file could not be renamed to '\(fileName)'."
        }
    }
}

@MainActor
final class CaptureLibrary: ObservableObject {
    @Published private(set) var items: [CaptureItem] = []
    @Published var selectedItemID: CaptureItem.ID?

    let rootURL: URL
    let mediaURL: URL
    private let metadataURL: URL
    private let fileManager: FileManager

    var selectedItem: CaptureItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let picturesURL = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        self.rootURL = picturesURL.appendingPathComponent("Quicky", isDirectory: true)
        self.mediaURL = rootURL.appendingPathComponent("Media", isDirectory: true)
        self.metadataURL = rootURL.appendingPathComponent("Library.json", isDirectory: false)

        try? fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        load()
    }

    func selectMostRecentIfNeeded() {
        if selectedItemID == nil {
            selectedItemID = items.first?.id
        }
    }

    func refreshFromDisk() {
        load()
    }

    func fileURL(for item: CaptureItem) -> URL {
        mediaURL.appendingPathComponent(item.fileName, isDirectory: false)
    }

    func makeMediaURL(kind: CaptureKind) -> URL {
        let stamp = DateFormatters.fileStamp.string(from: Date())
        let baseName = "\(kind.rawValue)-\(stamp)"
        var candidate = mediaURL
            .appendingPathComponent(baseName, isDirectory: false)
            .appendingPathExtension(kind.fileExtension)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = mediaURL
                .appendingPathComponent("\(baseName)-\(suffix)", isDirectory: false)
                .appendingPathExtension(kind.fileExtension)
            suffix += 1
        }

        return candidate
    }

    @discardableResult
    func addItem(
        kind: CaptureKind,
        fileURL: URL,
        width: Int,
        height: Int,
        duration: TimeInterval? = nil
    ) -> CaptureItem {
        let createdAt = Date()
        let title = "\(kind.displayName) \(DateFormatters.captureTitle.string(from: createdAt))"
        let finalURL = consistentMediaURL(for: fileURL, title: title, kind: kind)
        let item = CaptureItem(
            kind: kind,
            title: title,
            fileName: finalURL.lastPathComponent,
            createdAt: createdAt,
            width: width,
            height: height,
            duration: duration
        )
        items.insert(item, at: 0)
        selectedItemID = item.id
        save()
        return item
    }

    func delete(_ item: CaptureItem) {
        try? fileManager.removeItem(at: fileURL(for: item))
        items.removeAll { $0.id == item.id }
        if selectedItemID == item.id {
            selectedItemID = items.first?.id
        }
        save()
    }

    func rename(_ item: CaptureItem, to title: String) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        var updatedItem = items[index]
        let currentFileURL = fileURL(for: updatedItem)
        let newFileURL = uniqueMediaURL(
            forTitle: trimmedTitle,
            fileExtension: currentFileURL.pathExtension.isEmpty ? updatedItem.kind.fileExtension : currentFileURL.pathExtension,
            excluding: currentFileURL
        )

        if !sameFilePath(currentFileURL, newFileURL) {
            guard fileManager.fileExists(atPath: currentFileURL.path) else {
                throw CaptureLibraryError.missingFile(currentFileURL.lastPathComponent)
            }

            do {
                try fileManager.moveItem(at: currentFileURL, to: newFileURL)
            } catch {
                throw CaptureLibraryError.unableToRename(newFileURL.lastPathComponent)
            }

            updatedItem.fileName = newFileURL.lastPathComponent
        }
        updatedItem.title = trimmedTitle
        items[index] = updatedItem
        save()
    }

    private func uniqueMediaURL(forTitle title: String, fileExtension: String, excluding currentURL: URL) -> URL {
        let stem = safeFileStem(from: title)
        var candidate = mediaURL
            .appendingPathComponent(stem, isDirectory: false)
            .appendingPathExtension(fileExtension)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path), !sameFilePath(candidate, currentURL) {
            candidate = mediaURL
                .appendingPathComponent("\(stem)-\(suffix)", isDirectory: false)
                .appendingPathExtension(fileExtension)
            suffix += 1
        }

        return candidate
    }

    private func consistentMediaURL(for url: URL, title: String, kind: CaptureKind) -> URL {
        let fileExtension = url.pathExtension.isEmpty ? kind.fileExtension : url.pathExtension
        let targetURL = uniqueMediaURL(forTitle: title, fileExtension: fileExtension, excluding: url)
        guard !sameFilePath(url, targetURL) else {
            return url
        }

        do {
            try fileManager.moveItem(at: url, to: targetURL)
            return targetURL
        } catch {
            return url
        }
    }

    private func safeFileStem(from title: String) -> String {
        var stem = title.replacingOccurrences(
            of: #"[\/:\?\%*\|"<>]+"#,
            with: "-",
            options: .regularExpression
        )
        stem = stem.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return stem.isEmpty ? "capture" : stem
    }

    private func sameFilePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decodedItems = try decoder.decode([CaptureItem].self, from: data)
            var changed = false
            items = reconcile(decodedItems, changed: &changed)
            if selectedItemID.map({ id in !items.contains { $0.id == id } }) == true {
                selectedItemID = items.first?.id
                changed = true
            }
            if changed {
                save()
            }
        } catch {
            items = []
        }
    }

    private func reconcile(_ decodedItems: [CaptureItem], changed: inout Bool) -> [CaptureItem] {
        var reconciledItems: [CaptureItem] = []
        var usedPaths = Set<String>()

        for decodedItem in decodedItems {
            guard var item = reconcile(decodedItem, usedPaths: &usedPaths, changed: &changed) else {
                changed = true
                continue
            }

            let url = fileURL(for: item)
            usedPaths.insert(url.standardizedFileURL.path)
            item.fileName = url.lastPathComponent
            reconciledItems.append(item)
        }

        return reconciledItems
    }

    private func reconcile(_ item: CaptureItem, usedPaths: inout Set<String>, changed: inout Bool) -> CaptureItem? {
        var item = item
        var url = fileURL(for: item)

        if !isUsableMedia(at: url) {
            guard let recoveredURL = recoverRenamedFile(for: item, excluding: usedPaths) else {
                changed = true
                return nil
            }
            item.fileName = recoveredURL.lastPathComponent
            item.title = displayTitle(fromFileStem: recoveredURL.deletingPathExtension().lastPathComponent)
            url = recoveredURL
            changed = true
        }

        if isLegacyGeneratedName(url.deletingPathExtension().lastPathComponent) {
            let targetURL = consistentMediaURL(for: url, title: item.title, kind: item.kind)
            if !sameFilePath(url, targetURL) {
                item.fileName = targetURL.lastPathComponent
                url = targetURL
                changed = true
            }
        } else {
            let fileTitle = displayTitle(fromFileStem: url.deletingPathExtension().lastPathComponent)
            if safeFileStem(from: fileTitle) != safeFileStem(from: item.title) {
                item.title = fileTitle
                changed = true
            }
        }

        return item
    }

    private func isUsableMedia(at url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        let fileSize = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        if fileSize <= 0 {
            try? fileManager.removeItem(at: url)
            return false
        }

        return true
    }

    private func recoverRenamedFile(for item: CaptureItem, excluding usedPaths: Set<String>) -> URL? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: mediaURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = urls.compactMap { url -> (url: URL, distance: TimeInterval)? in
            guard url.pathExtension.lowercased() == item.kind.fileExtension,
                  !usedPaths.contains(url.standardizedFileURL.path),
                  isUsableMedia(at: url) else {
                return nil
            }

            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let dates = [values?.creationDate, values?.contentModificationDate].compactMap { $0 }
            guard let distance = dates.map({ abs($0.timeIntervalSince(item.createdAt)) }).min(),
                  distance < 300 else {
                return nil
            }
            return (url, distance)
        }

        return candidates.min { $0.distance < $1.distance }?.url
    }

    private func isLegacyGeneratedName(_ stem: String) -> Bool {
        stem.range(of: #"^(screenshot|recording)-\d{8}-\d{6}"#, options: .regularExpression) != nil
    }

    private func displayTitle(fromFileStem stem: String) -> String {
        var title = stem.replacingOccurrences(of: "_", with: " ")
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return title.isEmpty ? "Capture" : title
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: metadataURL, options: [.atomic])
        } catch {
            assertionFailure("Unable to save Quicky library metadata: \(error)")
        }
    }
}
