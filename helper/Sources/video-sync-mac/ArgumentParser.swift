import Foundation

struct CLIArguments {
    private let values: [String]

    init(_ values: [String] = CommandLine.arguments) {
        self.values = values
    }

    var command: String {
        values.dropFirst().first ?? "help"
    }

    func value(after flag: String) -> String? {
        guard let index = values.firstIndex(of: flag) else {
            return nil
        }
        let next = values.index(after: index)
        guard next < values.endIndex else {
            return nil
        }
        return values[next]
    }

    func int(after flag: String, default defaultValue: Int) -> Int {
        value(after: flag).flatMap(Int.init) ?? defaultValue
    }
}
