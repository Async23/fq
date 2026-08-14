// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "fq",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "fq", targets: ["fq"])
  ],
  targets: [
    .target(name: "FQCore"),
    .target(
      name: "FQMacOS",
      dependencies: ["FQCore"],
      linkerSettings: [
        .linkedFramework("AppKit")
      ]
    ),
    .executableTarget(
      name: "fq",
      dependencies: ["FQMacOS"]
    ),
    .testTarget(
      name: "FQCoreTests",
      dependencies: ["FQCore"]
    ),
    .testTarget(
      name: "FQMacOSTests",
      dependencies: ["FQCore", "FQMacOS"]
    ),
  ]
)
