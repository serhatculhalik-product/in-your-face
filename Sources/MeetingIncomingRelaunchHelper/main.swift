import Darwin
import Foundation
import MeetingIncomingHelperSupport

do {
    let bootstrap = try MeetingIncomingHelperBootstrap.load(
        arguments: CommandLine.arguments,
        helperExecutableURL: currentExecutableURL(),
        homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
    )
    defer { try? FileManager.default.removeItem(at: bootstrap.operationFileURL) }
    let runner = RelaunchRunner(
        environment: bootstrap.environment,
        parentWaiter: SystemParentProcessWaiter(),
        commandRunner: SystemHelperCommandRunner()
    )
    _ = try runner.run(operation: bootstrap.operation)
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? "Relaunch failed."
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(EXIT_FAILURE)
}

private func currentExecutableURL() -> URL {
    let workingDirectoryURL = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    return URL(
        fileURLWithPath: CommandLine.arguments[0],
        relativeTo: workingDirectoryURL
    ).standardizedFileURL
}
