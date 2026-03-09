// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "MoviePilot-TV",
  platforms: [
    .tvOS(.v17)
  ],
  products: [
    .library(
      name: "MoviePilot-TVLib",
      targets: ["MoviePilot-TV"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/tevelee/SwiftUI-Flow.git", from: "3.1.1"),
    .package(url: "https://github.com/malcommac/SwiftDate.git", from: "7.0.0"),
    .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.8.0"),
  ],
  targets: [
    .target(
      name: "MoviePilot-TV",
      dependencies: [
        .product(name: "Flow", package: "SwiftUI-Flow"),
        .product(name: "SwiftDate", package: "SwiftDate"),
        .product(name: "Kingfisher", package: "Kingfisher"),
      ],
      path: "MoviePilot-TV",
      exclude: [],
      sources: nil  // Defaults to all source files in path
    )
  ]
)
