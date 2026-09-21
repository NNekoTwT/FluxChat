//
//  MessageEntity.swift
//  SwiftChat
//
//  Created on 09/20/26.
//  Copyright © 2026 Sacha Servan-Schreiber. All rights reserved.
//

import Foundation
import SwiftData

/// SwiftData entity that mirrors a `Message` on disk.
///
/// Transient streaming state (`isThinking`, `isStreaming`, content/thinking
/// chunks, `urlFetches`, etc.) is intentionally NOT stored; it is always reset
/// on restore so old conversations never appear to still be generating.
@Model
final class MessageEntity {
    @Attribute(.unique) var id: String
    var roleRaw: String
    var content: String
    var thoughts: String?
    var timestamp: Date
    var generationTimeSeconds: Double?
    var isCollapsed: Bool
    var streamError: String?
    var isRequestError: Bool
    var webSearchStateData: Data?
    var attachmentMetaData: Data?
    /// Preserves message order (SwiftData to-many relationships do not guarantee it).
    var orderIndex: Int

    var chat: ChatEntity?

    init(
        id: String,
        roleRaw: String,
        content: String,
        thoughts: String?,
        timestamp: Date,
        generationTimeSeconds: Double?,
        isCollapsed: Bool,
        streamError: String?,
        isRequestError: Bool,
        webSearchStateData: Data?,
        attachmentMetaData: Data?,
        orderIndex: Int
    ) {
        self.id = id
        self.roleRaw = roleRaw
        self.content = content
        self.thoughts = thoughts
        self.timestamp = timestamp
        self.generationTimeSeconds = generationTimeSeconds
        self.isCollapsed = isCollapsed
        self.streamError = streamError
        self.isRequestError = isRequestError
        self.webSearchStateData = webSearchStateData
        self.attachmentMetaData = attachmentMetaData
        self.orderIndex = orderIndex
    }
}
