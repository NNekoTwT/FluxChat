//
//  ChatEntity.swift
//  SwiftChat
//
//  Created on 09/20/26.
//  Copyright © 2026 Sacha Servan-Schreiber. All rights reserved.
//

import Foundation
import SwiftData

/// SwiftData entity that mirrors a `Chat` conversation on disk.
@Model
final class ChatEntity {
    @Attribute(.unique) var id: String
    var title: String
    var titleStateRaw: String
    var createdAt: Date
    var modelTypeId: String
    var language: String?

    @Relationship(deleteRule: .cascade, inverse: \MessageEntity.chat)
    var messages: [MessageEntity] = []

    init(
        id: String,
        title: String,
        titleStateRaw: String,
        createdAt: Date,
        modelTypeId: String,
        language: String?
    ) {
        self.id = id
        self.title = title
        self.titleStateRaw = titleStateRaw
        self.createdAt = createdAt
        self.modelTypeId = modelTypeId
        self.language = language
    }
}
