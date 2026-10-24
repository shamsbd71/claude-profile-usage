import Foundation

public protocol KeychainAccess: Sendable {
    /// Returns nil when the item does not exist.
    func read(service: String) throws -> (data: Data, account: String)?
    func write(service: String, account: String, data: Data) throws
}

public enum KeychainError: Error, Equatable {
    case commandFailed(Int32)
    case timedOut
}

/// Talks to the login Keychain through /usr/bin/security. Claude Code creates its items with
/// that same binary, so the item ACL already trusts it and no access prompt appears.
public struct SecurityCLIKeychain: KeychainAccess {
    static let tool = "/usr/bin/security"
    static let itemNotFound: Int32 = 44
    /// `security -i` reads commands line by line from a fixed buffer; longer payloads go via argv
    /// (Claude Code does the same).
    static let stdinLimit = 4000

    public init() {}

    public func read(service: String) throws -> (data: Data, account: String)? {
        let secret = try Self.run(["find-generic-password", "-s", service, "-w"])
        if secret.status == Self.itemNotFound { return nil }
        guard secret.status == 0 else { throw KeychainError.commandFailed(secret.status) }
        let attrs = try Self.run(["find-generic-password", "-s", service])
        let account = Self.parseAccount(String(decoding: attrs.stdout, as: UTF8.self)) ?? NSUserName()
        return (Self.decodePassword(secret.stdout), account)
    }

    public func write(service: String, account: String, data: Data) throws {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -a \(Self.quote(account)) -s \(Self.quote(service)) -X \(hex)\n"
        let result = command.utf8.count <= Self.stdinLimit
            ? try Self.run(["-i"], stdin: Data(command.utf8))
            : try Self.run(["add-generic-password", "-U", "-a", account, "-s", service, "-X", hex])
        guard result.status == 0 else { throw KeychainError.commandFailed(result.status) }
    }

    static func parseAccount(_ dump: String) -> String? {
        guard let range = dump.range(of: #""acct"<blob>="([^"]*)""#, options: .regularExpression) else { return nil }
        let match = dump[range]
        return String(match.dropFirst(#""acct"<blob>=""#.count).dropLast())
    }

    /// `security -w` prints the secret as text, or as bare hex when it holds non-printable bytes.
    static func decodePassword(_ raw: Data) -> Data {
        var text = String(decoding: raw, as: UTF8.self)
        if text.hasSuffix("\n") { text.removeLast() }
        if !text.hasPrefix("{"), text.count % 2 == 0, text.allSatisfy(\.isHexDigit) {
            var bytes = Data()
            var i = text.startIndex
            while i < text.endIndex {
                let j = text.index(i, offsetBy: 2)
                bytes.append(UInt8(text[i..<j], radix: 16)!)
                i = j
            }
            return bytes
        }
        return Data(text.utf8)
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Runs `tool` with a hard timeout so a hung `security` (e.g. a locked Keychain) can never
    /// stall a refresh forever. stderr is discarded; stdout is drained concurrently.
    static func run(_ args: [String], tool: String = tool, stdin: Data? = nil,
                    timeout: TimeInterval = 10) throws -> (status: Int32, stdout: Data) {
        final class Box: @unchecked Sendable { var data = Data() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let inp = stdin == nil ? nil : Pipe()
        p.standardInput = inp ?? FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        try p.run()

        let box = Box()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.data = out.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        if let stdin, let inp {
            inp.fileHandleForWriting.write(stdin)
            try? inp.fileHandleForWriting.close()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            throw KeychainError.timedOut
        }
        drained.wait()
        return (p.terminationStatus, box.data)
    }
}
