import Foundation

enum CodexRPC {
    static let allowedOutgoingMethods: Set<String> = [
        "initialize",
        "initialized",
        "account/read",
        "account/rateLimits/read",
    ]

    static func initialize(version: String) -> Data {
        line([
            "method": "initialize",
            "id": 0,
            "params": [
                "clientInfo": [
                    "name": "tokens_piggy_bank",
                    "title": "Tokens Piggy Bank",
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

    static let accountRead = line([
        "method": "account/read",
        "id": 2,
        "params": ["refreshToken": false],
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
