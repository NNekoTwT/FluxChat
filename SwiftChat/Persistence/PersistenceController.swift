//
//  PersistenceController.swift
//  SwiftChat
//
//  Created on 09/20/26.
//  Copyright © 2026 Sacha Servan-Schreiber. All rights reserved.
//

import Foundation
import SwiftData

/// Owns the SwiftData `ModelContainer` for the app.
///
/// If the on-disk store cannot be created, it falls back to an in-memory store;
/// only if even that fails does it disable persistence entirely (`container` is
/// `nil`). In every failure case the app keeps running — it just won't remember
/// history across launches.
@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer?

    private init() {
        let schema = Schema([ChatEntity.self, MessageEntity.self])

        if let diskContainer = try? ModelContainer(for: schema) {
            container = diskContainer
            return
        }
        print("[ChatPersistence] Failed to create on-disk ModelContainer. Falling back to in-memory store.")

        let inMemoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try? ModelContainer(for: schema, configurations: [inMemoryConfiguration])
        if container == nil {
            print("[ChatPersistence] Failed to create in-memory ModelContainer. Local persistence is disabled.")
        }
    }
}
