//
//  DittoManager.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 9/26/25.
//

import DittoSwift

final class DittoManager {
    static let shared = try? DittoManager()

    public let ditto: Ditto?

    private init() throws {
        let cloudURL = URL(string: "YOUR_BIG_PEER_URL")!
        let config = DittoConfig(databaseID: "YOUR_APP_ID", connect: .server(url: cloudURL))
        let ditto = try Ditto.openSync(config: config)
        try ditto.disableSyncWithV3()
        Task {
            try await ditto.store.execute(query: "ALTER SYSTEM SET DQL_STRICT_MODE = false")
        }
        try ditto.sync.registerSubscription(query: "SELECT * FROM drawings")
        try ditto.sync.start()
        self.ditto = ditto
    }
}
