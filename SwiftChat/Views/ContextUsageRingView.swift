//
//  ContextUsageRingView.swift
//  SwiftChat
//
//  Created on 09/21/26.
//

import SwiftUI

/// Small tappable ring in the message input bar showing the estimated fraction of
/// the model's context window currently used. Tapping reveals a detail popover.
struct ContextUsageRingView: View {
    let usage: ContextUsageSnapshot

    @State private var showPopover = false

    private var ringColor: Color {
        switch usage.percentage {
        case ..<0.5: return .green
        case ..<0.8: return .orange
        default: return .red
        }
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.001, usage.percentage))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            ContextUsagePopover(usage: usage)
        }
    }
}

/// Detail popover shown when the ring is tapped.
private struct ContextUsagePopover: View {
    let usage: ContextUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(abbreviatedTokens(usage.estimatedTokens)) / \(abbreviatedTokens(usage.contextWindowTokens)) tokens")
                    .font(.system(size: 17, weight: .semibold))
                Text(usage.modelName)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            ProgressView(value: usage.percentage)
                .progressViewStyle(.linear)

            if let input = usage.lastInputTokens, let output = usage.lastOutputTokens {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last request")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Input \(abbreviatedTokens(input)) · Output \(abbreviatedTokens(output))")
                        .font(.system(size: 13))
                }
            }
        }
        .padding(16)
        .frame(minWidth: 220)
    }
}

/// Formats a token count into a compact human-readable string ("52K", "1.05M").
private func abbreviatedTokens(_ n: Int) -> String {
    if n >= 1_000_000 {
        return trimTrailingZeros(String(format: "%.2f", Double(n) / 1_000_000)) + "M"
    } else if n >= 1_000 {
        return trimTrailingZeros(String(format: "%.1f", Double(n) / 1_000)) + "K"
    }
    return "\(n)"
}

private func trimTrailingZeros(_ s: String) -> String {
    var result = s
    if result.contains(".") {
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
    }
    return result
}
