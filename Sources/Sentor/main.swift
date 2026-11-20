import Foundation
import SwiftUI

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--cli") || args.contains("--headless") || args.contains("--silent") {
    let code = TransferEngine.runCLI(arguments: args)
    exit(code)
} else {
    SentorApp.main()
}
