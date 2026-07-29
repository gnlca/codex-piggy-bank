import Foundation

enum CodexRPC {
    static let allowedOutgoingMethods: Set<String> = [
        "initialize",
        "initialized",
        "account/rateLimits/read",
    ]

    static func initialize(version: String) -> Data {
        line([
            "method": "initialize",
            "id": 0,
            "params": [
                "clientInfo": [
                    "name": "codex_reset_alert",
                    "title": "Codex Piggy Bank",
                    "version": version,
                ],
            ],
        ])
    }

    static let initialized = line([
        "method": "initialized",
        "params": [:],
    ])

    static let rateLimitsRead = line([
        "method": "account/rateLimits/read",
        "id": 1,
    ])

    private static func line(_ object: [String: Any]) -> Data {
        precondition(
            (object["method"] as? String).map(allowedOutgoingMethods.contains) == true,
            "Attempted to encode a non-read-only Codex RPC method"
        )
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data + Data([0x0A])
    }
}
