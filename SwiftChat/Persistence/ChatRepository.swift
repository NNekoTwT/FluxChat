//
//  ChatRepository.swift
//  SwiftChat
//
//  Created on 09/20/26.
//  Copyright © 2026 Sacha Servan-Schreiber. All rights reserved.
//

import Foundation
import SwiftData

/// Minimal persisted metadata for an attachment.
///
/// Binary payloads (base64 image data, extracted document text) are intentionally
/// NOT persisted in the first version. Only enough metadata is kept so a restored
/// message can still indicate that an attachment existed (file name / type / size).
struct AttachmentMetadata: Codable {
    let id: String
    let type: String
    let fileName: String
    let mimeType: String?
    let description: String?
    let fileSize: Int64

    init(attachment: Attachment) {
        self.id = attachment.id
        self.type = attachment.type.rawValue
        self.fileName = attachment.fileName
        self.mimeType = attachment.mimeType
        self.description = attachment.description
        self.fileSize = attachment.fileSize
    }

    func toAttachment() -> Attachment {
        Attachment(
            id: id,
            type: AttachmentType(rawValue: type) ?? .document,
            fileName: fileName,
            mimeType: mimeType,
            base64: nil,
            thumbnailBase64: nil,
            textContent: nil,
            description: description,
            fileSize: fileSize,
            encryptionKey: nil,
            processingState: .completed
        )
    }
}

/// CRUD + mapping layer between the in-memory `Chat` / `Message` value types and
/// the SwiftData `ChatEntity` / `MessageEntity` models.
///
/// Every SwiftData operation is wrapped in do/catch so a persistence failure never
/// crashes the app; failures are logged with a `[ChatPersistence]` prefix and the
/// in-memory chat UI keeps working as best it can.
@MainActor
final class ChatRepository {
    static let shared = ChatRepository()

    private let container: ModelContainer?
    private lazy var modelContext: ModelContext? = {
        container.map { ModelContext($0) }
    }()

    private init() {
        container = PersistenceController.shared.container
    }

    // MARK: - Load

    /// Returns all persisted chats, newest first.
    func loadChats() -> [Chat] {
        guard let modelContext else { return [] }
        do {
            let descriptor = FetchDescriptor<ChatEntity>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map { Self.chat(from: $0) }
        } catch {
            print("[ChatPersistence] Failed to fetch chats: \(error)")
            return []
        }
    }

    // MARK: - Save / Delete

    func saveChat(_ chat: Chat) {
        guard let modelContext else { return }
        do {
            let entity = try fetchOrCreateChatEntity(id: chat.id, in: modelContext)
            entity.title = chat.title
            entity.titleStateRaw = chat.titleState.rawValue
            entity.createdAt = chat.createdAt
            entity.modelTypeId = chat.modelType.id
            entity.language = chat.language

            // Replace the message list wholesale so order is preserved and
            // truncations (regenerate / edit) are reflected correctly.
            for message in entity.messages {
                modelContext.delete(message)
            }
            entity.messages = chat.messages.enumerated().map { index, message in
                let messageEntity = Self.entity(from: message, orderIndex: index)
                messageEntity.chat = entity
                return messageEntity
            }

            try modelContext.save()
        } catch {
            print("[ChatPersistence] Failed to save chat \(chat.id): \(error)")
        }
    }

    func deleteChat(id: String) {
        guard let modelContext else { return }
        do {
            let descriptor = FetchDescriptor<ChatEntity>(predicate: #Predicate { $0.id == id })
            if let entity = try modelContext.fetch(descriptor).first {
                modelContext.delete(entity)
                try modelContext.save()
            }
        } catch {
            print("[ChatPersistence] Failed to delete chat \(id): \(error)")
        }
    }

    // MARK: - Mapping

    private static func chat(from entity: ChatEntity) -> Chat {
        let messages = entity.messages
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { message(from: $0) }

        let titleState = Chat.TitleState(rawValue: entity.titleStateRaw)
            ?? Chat.deriveTitleState(for: entity.title, messages: messages)

        return Chat(
            id: entity.id,
            title: entity.title,
            titleState: titleState,
            messages: messages,
            createdAt: entity.createdAt,
            modelType: resolveModelType(id: entity.modelTypeId),
            language: entity.language
        )
    }

    private static func message(from entity: MessageEntity) -> Message {
        var message = Message(
            id: entity.id,
            role: MessageRole(rawValue: entity.roleRaw) ?? .user,
            content: entity.content,
            thoughts: entity.thoughts,
            timestamp: entity.timestamp,
            isCollapsed: entity.isCollapsed,
            generationTimeSeconds: entity.generationTimeSeconds,
            webSearchState: webSearchState(from: entity.webSearchStateData),
            attachments: attachments(from: entity.attachmentMetaData)
        )
        // Terminal error state is persisted so a failed response can still be
        // regenerated after a restart.
        message.streamError = entity.streamError
        message.isRequestError = entity.isRequestError
        return message
    }

    private static func entity(from message: Message, orderIndex: Int) -> MessageEntity {
        let webSearchData: Data?
        if let state = message.webSearchState {
            webSearchData = try? JSONEncoder().encode(state)
        } else {
            webSearchData = nil
        }

        let attachmentData: Data?
        if !message.attachments.isEmpty {
            attachmentData = try? JSONEncoder().encode(message.attachments.map { AttachmentMetadata(attachment: $0) })
        } else {
            attachmentData = nil
        }

        return MessageEntity(
            id: message.id,
            roleRaw: message.role.rawValue,
            content: message.content,
            thoughts: message.thoughts,
            timestamp: message.timestamp,
            generationTimeSeconds: message.generationTimeSeconds,
            isCollapsed: message.isCollapsed,
            streamError: message.streamError,
            isRequestError: message.isRequestError,
            webSearchStateData: webSearchData,
            attachmentMetaData: attachmentData,
            orderIndex: orderIndex
        )
    }

    private static func resolveModelType(id: String) -> ModelType {
        let models = AppConfig.shared.availableModels
        if let match = models.first(where: { $0.id == id }) {
            return match
        }
        // Unknown or removed model: fall back to the first available, or a bare
        // placeholder built from the stored id so we never crash.
        return models.first ?? ModelType(
            id: id,
            displayName: id,
            fullName: id,
            iconName: "openai-icon",
            isMultimodal: false,
            contextWindowTokens: ModelType.fallbackContextWindowTokens
        )
    }

    private static func webSearchState(from data: Data?) -> WebSearchState? {
        guard let data else { return nil }
        guard var state = try? JSONDecoder().decode(WebSearchState.self, from: data) else { return nil }
        // `.searching` is a transient streaming state; never restore it.
        if state.status == .searching {
            state.status = .completed
        }
        return state
    }

    private static func attachments(from data: Data?) -> [Attachment] {
        guard let data,
              let metadata = try? JSONDecoder().decode([AttachmentMetadata].self, from: data) else {
            return []
        }
        return metadata.map { $0.toAttachment() }
    }

    private func fetchOrCreateChatEntity(id: String, in context: ModelContext) throws -> ChatEntity {
        let descriptor = FetchDescriptor<ChatEntity>(predicate: #Predicate { $0.id == id })
        if let entity = try context.fetch(descriptor).first {
            return entity
        }
        let entity = ChatEntity(
            id: id,
            title: "",
            titleStateRaw: "",
            createdAt: Date(),
            modelTypeId: "",
            language: nil
        )
        context.insert(entity)
        return entity
    }
}
