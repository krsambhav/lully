// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Lully", platforms: [.macOS(.v14)], products: [.executable(name: "Lully", targets: ["Lully"])], targets: [.executableTarget(name: "Lully")])
