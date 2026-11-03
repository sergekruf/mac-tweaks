// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacTweaks",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MacTweaks", dependencies: ["KeyChord", "ScrollWheel", "PointerMath"], path: "Sources/MacTweaks"),
        // Логика сочетаний без зависимостей от системы — проверяется тестами
        .target(name: "KeyChord", path: "Sources/KeyChord"),
        .testTarget(name: "KeyChordTests", dependencies: ["KeyChord"], path: "Tests/KeyChordTests"),
        // Преобразование событий колеса мыши — тоже без зависимостей от системы
        .target(name: "ScrollWheel", path: "Sources/ScrollWheel"),
        .testTarget(name: "ScrollWheelTests", dependencies: ["ScrollWheel"], path: "Tests/ScrollWheelTests"),
        // Целевые значения ускорения и скорости указателя мыши
        .target(name: "PointerMath", path: "Sources/PointerMath"),
        .testTarget(name: "PointerMathTests", dependencies: ["PointerMath"], path: "Tests/PointerMathTests"),
    ]
)
