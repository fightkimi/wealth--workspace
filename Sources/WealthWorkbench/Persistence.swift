import Foundation

protocol PortfolioPersisting {
    func load() throws -> PortfolioData
    func save(_ value: PortfolioData) throws
    var displayPath: String { get }
}

protocol APIKeyPersisting {
    func load() throws -> String?
    func save(_ value: String) throws
    func delete() throws
    var displayPath: String { get }
}

struct APIKeyFileStore: APIKeyPersisting {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = support
                .appendingPathComponent("WealthWorkbench", isDirectory: true)
                .appendingPathComponent("Credentials", isDirectory: true)
                .appendingPathComponent("twelve-data-api-key.txt")
        }
    }

    var displayPath: String { fileURL.path }

    func load() throws -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func save(_ value: String) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try Data(value.utf8).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

struct PortfolioFileStore: PortfolioPersisting {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = support
                .appendingPathComponent("WealthWorkbench", isDirectory: true)
                .appendingPathComponent("portfolio.json")
        }
    }

    var displayPath: String { fileURL.path }

    func load() throws -> PortfolioData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return PortfolioData() }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.portfolio.decode(PortfolioData.self, from: data)
    }

    func save(_ value: PortfolioData) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.portfolio.encode(value)
        // NSFileProtectionComplete is an iOS-style protection class and is not
        // consistently supported for arbitrary macOS paths. Atomic replacement
        // plus owner-only POSIX permissions is reliable for this local data file.
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

extension JSONEncoder {
    static var portfolio: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var portfolio: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
