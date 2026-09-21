//
//  AppConfig.swift
//  SwiftChat
//
//  Created on 03/25/26.
//  Copyright © 2026 Sacha Servan-Schreiber. All rights reserved.
//

import Foundation
import Combine
import OpenAI

/// A model available for chat
struct ModelType: Identifiable, Codable, Hashable, Equatable {
    let id: String
    let displayName: String
    let fullName: String
    let iconName: String
    let isMultimodal: Bool
    /// Maximum context window size, in tokens.
    let contextWindowTokens: Int

    var modelName: String { id }

    /// Fallback context window used when a model's window is unknown (legacy data
    /// or an unknown model id). Matches DeepSeek V4 Pro's 1M window.
    static let fallbackContextWindowTokens = 1_048_576

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ModelType, rhs: ModelType) -> Bool { lhs.id == rhs.id }

    init(
        id: String,
        displayName: String,
        fullName: String,
        iconName: String,
        isMultimodal: Bool,
        contextWindowTokens: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.fullName = fullName
        self.iconName = iconName
        self.isMultimodal = isMultimodal
        self.contextWindowTokens = contextWindowTokens
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, fullName, iconName, isMultimodal, contextWindowTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        fullName = try container.decode(String.self, forKey: .fullName)
        iconName = try container.decode(String.self, forKey: .iconName)
        isMultimodal = try container.decode(Bool.self, forKey: .isMultimodal)
        contextWindowTokens = try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens)
            ?? ModelType.fallbackContextWindowTokens
    }
}

/// Application-wide configuration
@MainActor
class AppConfig: ObservableObject {
    static let shared = AppConfig()

    // MARK: - Configuration

    /// Set your API key here or via environment
    var apiKey: String = "YOUR_APIKEY"

    /// OpenAI-compatible API host (no scheme, no path)
    var apiHost: String = "api.deepseek.com"

    /// Base path for the API
    var apiBasePath: String = "/v1"

    /// System prompt sent with every conversation
    var systemPrompt: String = "You are a helpful AI assistant."

    /// Additional rules appended to the system prompt
    var rules: String = ""

    // MARK: - State

    @Published private(set) var isInitialized = false
    @Published private(set) var initializationError: Error?
    @Published var currentModel: ModelType? {
        didSet {
            if let model = currentModel {
                UserDefaults.standard.set(model.id, forKey: "selectedModel")
            }
        }
    }
    @Published private(set) var availableModels: [ModelType] = []
    @Published private(set) var networkMonitor = NetworkMonitor()

    private init() {
        setupDefaultModels()
        loadLastSelectedModel()
        isInitialized = true
    }

    // MARK: - Models

    /// Override this to change available models
    private func setupDefaultModels() {
        availableModels = [
            ModelType(
                id: "deepseek-v4-pro",
                displayName: "DeepSeek V4 Pro",
                fullName: "DeepSeek V4 Pro",
                iconName: "openai-icon",
                isMultimodal: true,
                contextWindowTokens: 1_048_576
            )
        ]
    }

    private func loadLastSelectedModel() {
        if let savedId = UserDefaults.standard.string(forKey: "selectedModel"),
           let model = availableModels.first(where: { $0.id == savedId }) {
            currentModel = model
        } else {
            currentModel = availableModels.first
        }
    }

    func filteredModelTypes() -> [ModelType] {
        return availableModels
    }

    /// The model used for generating chat titles (nil = skip title generation)
    var titleModel: ModelType? {
        availableModels.first
    }

    // MARK: - OpenAI Client

    func makeClient() -> OpenAI {
        let config = OpenAI.Configuration(
            token: apiKey,
            host: "api.deepseek.com",
            scheme: "https",
            basePath: apiBasePath,
            parsingOptions: .relaxed
        )
        return OpenAI(configuration: config)
    }
}
