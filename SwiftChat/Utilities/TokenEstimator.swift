//
//  TokenEstimator.swift
//  SwiftChat
//
//  Created on 09/21/26.
//

import Foundation

/// Lightweight heuristic token estimator for the context-window usage indicator.
///
/// This is intentionally NOT a byte-exact BPE tokenizer — that would require a
/// tokenizer dependency. It estimates well enough to render a usage ring, and is
/// only used to *predict* the size of the *next* request (which the API cannot
/// tell us ahead of time). The authoritative token counts come from the API's
/// `usage` payload; see `TokenUsage` below.
enum TokenEstimator {

    /// Rough token cost of a single image, assuming the app's ≤768px resizing.
    static let imageTokenEstimate = 1000

    /// Fixed per-message overhead (role / framing) added on top of the content.
    static let messageOverheadTokens = 4

    /// Estimates tokens for a plain-text string using a CJK-aware heuristic:
    /// CJK characters ≈ 1 token each; other non-whitespace characters ≈ 4 per token.
    static func estimateTokens(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var cjkCount = 0
        var otherCount = 0

        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                cjkCount += 1
            } else if !scalar.properties.isWhitespace {
                otherCount += 1
            }
        }

        let otherTokens = Int((Double(otherCount) / 4.0).rounded(.up))
        return cjkCount + otherTokens
    }

    /// Estimates tokens for a single message: content plus document text and images.
    ///
    /// `thoughts` is intentionally NOT counted — it is never sent to the API
    /// (see `ChatQueryBuilder.buildQuery`, which only sends assistant `content`).
    static func estimateMessageTokens(_ message: Message) -> Int {
        var total = messageOverheadTokens
        total += estimateTokens(for: message.content)
        for attachment in message.attachments {
            switch attachment.type {
            case .document:
                total += estimateTokens(for: attachment.textContent ?? "")
            case .image:
                total += imageTokenEstimate
            }
        }
        return total
    }

    /// Estimates the total context tokens the next request would send, mirroring
    /// `ChatQueryBuilder.buildQuery`: system prompt + rules + the last `maxMessages`
    /// messages. Only already-sent messages are counted (not the in-progress draft).
    static func estimateContextTokens(
        systemPrompt: String,
        rules: String,
        messages: [Message],
        maxMessages: Int
    ) -> Int {
        let fullPrompt = rules.isEmpty ? systemPrompt : systemPrompt + "\n\n" + rules
        var total = estimateTokens(for: fullPrompt)

        for message in messages.suffix(maxMessages) {
            total += estimateMessageTokens(message)
        }
        return total
    }

    // MARK: - Helpers

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,  // CJK Unified Ideographs
             0x3400...0x4DBF,  // CJK Unified Ideographs Extension A
             0xF900...0xFAFF,  // CJK Compatibility Ideographs
             0x3040...0x30FF,  // Hiragana + Katakana
             0xAC00...0xD7AF,  // Hangul syllables
             0x1100...0x11FF,  // Hangul Jamo
             0x3000...0x303F:  // CJK punctuation
            return true
        default:
            return false
        }
    }
}

/// Authoritative token counts reported by the API for the most recent completed
/// response (`response.completed` → `usage`).
struct TokenUsage {
    let input: Int
    let output: Int
}

/// Snapshot of the current conversation's context usage, consumed by the ring UI.
struct ContextUsageSnapshot {
    /// Estimated tokens the next request would send.
    let estimatedTokens: Int
    /// The current model's maximum context window, in tokens.
    let contextWindowTokens: Int
    let modelName: String
    /// Last request's actual input/output tokens (nil until the first response).
    let lastInputTokens: Int?
    let lastOutputTokens: Int?

    /// Fraction of the context window currently used, clamped to 0...1.
    var percentage: Double {
        guard contextWindowTokens > 0 else { return 0 }
        return min(1.0, Double(estimatedTokens) / Double(contextWindowTokens))
    }
}
