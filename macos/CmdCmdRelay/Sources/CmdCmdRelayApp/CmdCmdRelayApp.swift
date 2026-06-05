import Foundation

@main
enum CmdCmdRelayApp {
    static func main() {
        if TerminalRelayCommand.runIfRequested() {
            return
        }

        TerminalRelayCommand.printUsage()
    }
}
