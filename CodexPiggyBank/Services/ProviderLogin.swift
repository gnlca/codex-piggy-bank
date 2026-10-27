import AppKit

@MainActor
enum ProviderLogin {
    static func open(_ profile: ProviderProfile) throws {
        guard let executable = ProviderExecutableLocator.resolve(profile) else {
            throw ProviderConnectionError.executableNotFound(profile.kind)
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokens-piggy-bank-login", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        let script = directory.appendingPathComponent("\(profile.id).command")
        let command = loginCommand(profile, executable: executable)
        let contents = """
        #!/bin/zsh
        /bin/mkdir -p \(quote(profile.resolvedDirectory)) || exit 1
        \(command)
        result=$?
        /bin/rm -f -- \(quote(script.path))
        printf '\\nReturn to Tokens Piggy Bank and click Refresh.\\n'
        exit "$result"
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        guard NSWorkspace.shared.open(script) else {
            throw ProviderConnectionError.unavailable("Terminal could not open the sign-in command.")
        }
    }

    static func loginCommand(_ profile: ProviderProfile, executable: URL) -> String {
        let arguments = profile.kind == .codex ? "login" : "auth login"
        let variable = profile.kind.configurationVariable
        let configuration = profile.environment[variable].map { "\(variable)=\(quote($0))" }
            ?? "-u \(variable)"
        return "/usr/bin/env \(configuration) \(quote(executable.path)) \(arguments)"
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
