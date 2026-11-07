import CryptoKit
import Darwin
import Foundation

let folder = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/EdgeSwipe/UpdateSigning", isDirectory: true)
let path = folder.appendingPathComponent("ed25519.key")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
let key: Curve25519.Signing.PrivateKey
if FileManager.default.fileExists(atPath: path.path) {
    let contents = try String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let seed = Data(base64Encoded: contents), seed.count == 32 else { fatalError("Invalid existing EdgeSwipe update signing key") }
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
} else {
    key = Curve25519.Signing.PrivateKey()
    let descriptor = open(path.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else { fatalError("Could not create EdgeSwipe update signing key") }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try handle.write(contentsOf: Data(key.rawRepresentation.base64EncodedString().utf8))
    try handle.close()
}
if CommandLine.arguments.contains("--path") { print(path.path) }
else { print(key.publicKey.rawRepresentation.base64EncodedString()) }
