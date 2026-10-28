// Colori e vetro, in un posto solo.
// Regola (HIG, Liquid Glass): il vetro solo sui controlli che galleggiano (la barra delle schede, i pulsanti in fondo);
// il contenuto usa riempimenti standard. Riduci trasparenza e Aumenta contrasto li gestisce il sistema.
// Il testo fantasma usa il grigio dei segnaposto del sistema (GhostOverlay), non un colore nostro.

import AppKit
import SwiftUI

enum Palette {
    /// I colori del marchio, come l'icona: inchiostro, grigio del suggerimento, blu del cursore.
    static let ink = Color(red: 0.15, green: 0.17, blue: 0.21)
    static let ghost = Color(red: 0.69, green: 0.71, blue: 0.75)
    static let cursor = Color(red: 0.18, green: 0.49, blue: 0.96)
    /// Verde dei "tutto bene" (permesso concesso, modello pronto).
    static let calm = Color(red: 0.20, green: 0.70, blue: 0.42)
}

extension View {
    /// Vetro per i controlli che galleggiano. Mai per il contenuto.
    @ViewBuilder
    func glassSurface(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Pulsante di vetro (secondario).
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Il pulsante principale, uno per vista: vetro colorato.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Una scheda del contenuto: un velo chiaro con un filo di luce sul bordo alto. Statico, niente sfocature in più.
    func contentCard(padding: CGFloat = 12, radius: CGFloat = 12) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ContentCardBackground(radius: radius))
    }
}

private struct ContentCardBackground: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = scheme == .dark
        let strong = contrast == .increased
        content
            .background(dark ? Color.white.opacity(strong ? 0.12 : 0.07) : Color.white.opacity(strong ? 0.8 : 0.5), in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(dark ? 0.22 : 0.9), Color.white.opacity(dark ? 0.04 : 0.3)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            }
            .overlay {
                if strong { shape.strokeBorder(Color.primary.opacity(0.25), lineWidth: 1) }
            }
    }
}

/// Contenitore dei controlli di vetro: su macOS 26 le forme vicine si fondono e si trasformano insieme.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Un esempio di come appare un suggerimento: testo scritto, cursore, seguito in grigio. Per la guida e le impostazioni.
struct GhostPreview: View {
    var written: String
    var ghost: String
    var accept: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text(written)
                Rectangle().fill(Palette.cursor).frame(width: 2, height: 18).padding(.horizontal, 1)
                Text(ghost).foregroundStyle(Color(nsColor: .placeholderTextColor))
            }
            .font(.system(size: 15))
            .lineLimit(1)
            Text(accept)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Esempio: hai scritto %@ e il suggerimento è %@", written, ghost))
    }
}
