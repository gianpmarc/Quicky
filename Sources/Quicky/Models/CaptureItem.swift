import Foundation

struct CaptureItem: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: CaptureKind
    var title: String
    var fileName: String
    var createdAt: Date
    var width: Int
    var height: Int
    var duration: TimeInterval?

    init(
        id: UUID = UUID(),
        kind: CaptureKind,
        title: String,
        fileName: String,
        createdAt: Date = Date(),
        width: Int,
        height: Int,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.fileName = fileName
        self.createdAt = createdAt
        self.width = width
        self.height = height
        self.duration = duration
    }
}
