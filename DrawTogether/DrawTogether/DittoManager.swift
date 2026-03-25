//
//  DittoManager.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 9/26/25.
//

import DittoSwift

final class DittoManager {
    static let shared = try? DittoManager()

    public let ditto: Ditto

    private init() throws {
        let cloudURL = URL(string: Env.DITTO_WEBSOCKET_URL)!
        let config = DittoConfig(databaseID: Env.DITTO_APP_ID, connect: .server(url: cloudURL))
        let ditto = try Ditto.openSync(config: config)
        try ditto.disableSyncWithV3()
        ditto.auth?.expirationHandler = { ditto, secondsRemaining in
            ditto.auth?.login(
                token: Env.DITTO_PLAYGROUND_TOKEN,
                provider: .development
            ) { clientInfo, error in
                if let error = error {
                    NSLog("Ditto auth failed: %@", "\(error)")
                }
            }
        }
        Task {
            try await ditto.store.execute(query: "ALTER SYSTEM SET DQL_STRICT_MODE = false")
        }
        try ditto.sync.registerSubscription(query: "SELECT * FROM drawings")
        try ditto.sync.start()
        self.ditto = ditto
    }
}
