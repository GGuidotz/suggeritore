// Il testo fantasma: un pannello trasparente, senza ombra, che non prende il fuoco né i clic, appoggiato subito dopo
// il cursore del campo in cui scrivi, con lo stesso carattere quando l'app lo dice e il grigio dei segnaposto.
// Se l'app non dice dov'è il cursore, una piccola pillola in basso nel campo (o nello schermo).
// Le coordinate dell'AX hanno l'origine in alto a sinistra dello schermo principale; quelle di AppKit in basso.

import AppKit
import SwiftUI

@MainActor
final class GhostOverlay {
    private let panel: PassivePanel
    private let host: NSHostingView<GhostTextView>
    private(set) var isVisible = false

    init() {
        panel = PassivePanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        host = NSHostingView(rootView: GhostTextView(text: "", font: .systemFont(ofSize: 13), pill: false))
        panel.contentView = host
    }

    /// Mostra `text` dopo il cursore (`caret`, coordinate AX) o, senza cursore, in una pillola nel campo.
    func show(_ text: String, font: NSFont?, caret: CGRect?, fieldFrame: CGRect?) {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        if let caret {
            let font = font ?? NSFont.systemFont(ofSize: Swift.max(11, Swift.min(caret.height * 0.72, 28)))
            let measured = NSAttributedString(string: text, attributes: [.font: font]).size().width + 6
            let x = caret.minX + 1
            let origin = CGPoint(x: x, y: screenHeight - caret.maxY)
            let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: origin.x, y: origin.y + caret.height / 2)) }) ?? NSScreen.main
            var limit = (screen?.visibleFrame.maxX ?? origin.x + measured) - x - 6
            if let fieldFrame { limit = Swift.min(limit, fieldFrame.maxX - x - 4) }
            guard limit > 24 else { showPill(text, fieldFrame: fieldFrame, screenHeight: screenHeight); return }
            let width = Swift.min(measured, limit)
            let height = Swift.max(caret.height, font.pointSize * 1.3)
            host.rootView = GhostTextView(text: text, font: font, pill: false)
            panel.setFrame(NSRect(x: origin.x, y: origin.y - (height - caret.height) / 2, width: width, height: height), display: true)
        } else {
            showPill(text, fieldFrame: fieldFrame, screenHeight: screenHeight)
        }
        if !isVisible { panel.orderFrontRegardless() }
        isVisible = true
    }

    private func showPill(_ text: String, fieldFrame: CGRect?, screenHeight: CGFloat) {
        host.rootView = GhostTextView(text: text, font: .systemFont(ofSize: 13), pill: true)
        let size = host.fittingSize
        let width = Swift.min(size.width, 420), height = size.height
        var origin: CGPoint
        if let fieldFrame, fieldFrame.width > 60 {
            origin = CGPoint(x: fieldFrame.midX - width / 2, y: screenHeight - fieldFrame.maxY + 8)
        } else {
            let frame = NSScreen.main?.visibleFrame ?? .zero
            origin = CGPoint(x: frame.maxX - width - 20, y: frame.minY + 20)
        }
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
    }

    func hide() {
        guard isVisible else { return }
        panel.orderOut(nil)
        isVisible = false
    }
}

/// Un pannello che non diventa mai finestra principale né attiva.
final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct GhostTextView: View {
    var text: String
    var font: NSFont
    var pill: Bool

    var body: some View {
        if pill {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                .padding(10)
                .accessibilityLabel(L("Suggerimento: %@", text))
        } else {
            Text(text)
                .font(Font(font as CTFont))
                .foregroundStyle(Color(nsColor: .placeholderTextColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel(L("Suggerimento: %@", text))
        }
    }
}
