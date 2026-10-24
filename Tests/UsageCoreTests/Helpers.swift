import Foundation

func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cu-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
