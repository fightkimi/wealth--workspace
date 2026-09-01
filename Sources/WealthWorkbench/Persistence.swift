import Foundation

enum LocalAppDataPaths {
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("WealthWorkbench", isDirectory: true)
    }

    static var credentialsDirectory: URL {
        supportDirectory.appendingPathComponent("Credentials", isDirectory: true)
    }
}

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

struct OpenAICredential: Codable, Equatable {
    static let defaultEndpoint = "https://api.openai.com/v1/responses"

    var apiKey: String
    var endpoint: String
}

protocol OpenAICredentialPersisting {
    func load() throws -> OpenAICredential?
    func save(_ value: OpenAICredential) throws
    func delete() throws
    var displayPath: String { get }
}

struct OpenAICredentialFileStore: OpenAICredentialPersisting {
    let fileURL: URL
    private let legacyKeyFileURL: URL?

    init(fileURL: URL? = nil, legacyKeyFileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            self.legacyKeyFileURL = legacyKeyFileURL
        } else {
            self.fileURL = LocalAppDataPaths.credentialsDirectory
                .appendingPathComponent("openai-credentials.json")
            self.legacyKeyFileURL = legacyKeyFileURL ?? LocalAppDataPaths.credentialsDirectory
                .appendingPathComponent("openai-api-key.txt")
        }
    }

    var displayPath: String { fileURL.path }

    func load() throws -> OpenAICredential? {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(OpenAICredential.self, from: data)
            let key = decoded.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            let endpoint = decoded.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            return OpenAICredential(
                apiKey: key,
                endpoint: endpoint.isEmpty ? OpenAICredential.defaultEndpoint : endpoint
            )
        }

        guard let legacyKeyFileURL,
              let key = try APIKeyFileStore(fileURL: legacyKeyFileURL).load() else {
            return nil
        }
        let migrated = OpenAICredential(apiKey: key, endpoint: OpenAICredential.defaultEndpoint)
        try save(migrated)
        try? APIKeyFileStore(fileURL: legacyKeyFileURL).delete()
        return migrated
    }

    func save(_ value: OpenAICredential) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder.localConfiguration.encode(value)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func delete() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        if let legacyKeyFileURL, FileManager.default.fileExists(atPath: legacyKeyFileURL.path) {
            try FileManager.default.removeItem(at: legacyKeyFileURL)
        }
    }
}

struct AssistantPlacement: Codable, Equatable {
    var x: Double
    var y: Double
}

protocol AssistantPlacementPersisting {
    func load() throws -> AssistantPlacement?
    func save(_ value: AssistantPlacement) throws
    var displayPath: String { get }
}

struct AssistantPlacementFileStore: AssistantPlacementPersisting {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? LocalAppDataPaths.supportDirectory
            .appendingPathComponent("UIState", isDirectory: true)
            .appendingPathComponent("assistant-placement.json")
    }

    var displayPath: String { fileURL.path }

    func load() throws -> AssistantPlacement? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(AssistantPlacement.self, from: Data(contentsOf: fileURL))
    }

    func save(_ value: AssistantPlacement) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder.localConfiguration.encode(value)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

struct APIKeyFileStore: APIKeyPersisting {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.init(filename: "twelve-data-api-key.txt", fileURL: fileURL)
    }

    init(filename: String, fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = LocalAppDataPaths.credentialsDirectory
                .appendingPathComponent(filename)
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
            self.fileURL = LocalAppDataPaths.supportDirectory
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

    static var localConfiguration: JSONEncoder {
        let encoder = JSONEncoder()
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
