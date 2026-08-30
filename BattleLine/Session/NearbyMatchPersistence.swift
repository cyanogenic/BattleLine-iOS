import BattleLineCore
import Foundation

struct PersistedNearbyMatch: Codable, Sendable {
    let role: NearbyMatchRole
    let matchID: UUID
    let resumeToken: UUID
    let localSeat: PlayerID
    let localPlayerName: String
    let opponentName: String
    let pairingCode: String
    let advancedClaiming: Bool
    let game: BattleLineGame?
    let guestView: PlayerView?
    let guestClaimableFlagIndices: [Int]
    let processedCommandIDs: [UUID]
}

struct NearbyMatchPersistence: Sendable {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.fileURL = applicationSupport
            .appending(path: "BattleLine", directoryHint: .isDirectory)
            .appending(path: "nearby-match-v1.json", directoryHint: .notDirectory)
    }

    func load() -> PersistedNearbyMatch? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedNearbyMatch.self, from: data)
    }

    func save(_ match: PersistedNearbyMatch) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(match).write(to: fileURL, options: .atomic)
    }

    func clear() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
