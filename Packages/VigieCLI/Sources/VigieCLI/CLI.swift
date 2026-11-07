import Foundation
import Wire

/// Entry logic for the `vigie` command-line tool. Commands arrive in later stories.
public enum CLI {
    /// Localized usage text (AD-15 sample lookup).
    public static var usage: String {
        String(localized: "cli.usage", bundle: .module)
    }

    /// Runs the CLI with the given arguments (excluding the program name) and returns the exit code.
    public static func run(arguments: [String], output: (String) -> Void) -> Int32 {
        output(usage)
        return 0
    }
}
