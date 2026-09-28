import Foundation

/// A look applied on top of the user's prompt. Preview images ship in the app bundle
/// and were rendered locally with FLUX.2 Klein.
struct StylePreset: Identifiable, Equatable {
    enum Category: String, CaseIterable, Identifiable {
        case all = "All"
        case photo = "Photo"
        case art = "Art"
        var id: String { rawValue }
    }

    let id: String
    let name: String
    let category: Category
    let style: String

    var previewURL: URL? { Bundle.main.resourceURL?.appendingPathComponent("Presets/\(id).jpg") }

    static let all: [StylePreset] = [
        StylePreset(id: "cinematic", name: "Cinematic", category: .photo,
                    style: "cinematic film still, anamorphic lens, dramatic lighting, shallow depth of field, teal and orange color grade"),
        StylePreset(id: "vintage-film", name: "Vintage film", category: .photo,
                    style: "shot on 35mm film, soft grain, warm faded colors, nostalgic 1980s snapshot"),
        StylePreset(id: "monochrome", name: "Monochrome", category: .photo,
                    style: "black and white photograph, high contrast, deep shadows, fine grain, dramatic chiaroscuro"),
        StylePreset(id: "neon-noir", name: "Neon noir", category: .photo,
                    style: "neon-lit night scene, rain reflections, magenta and cyan glow, moody cyberpunk atmosphere"),
        StylePreset(id: "oil-painting", name: "Oil painting", category: .art,
                    style: "oil painting on canvas, visible brushstrokes, rich impasto texture, classical fine art lighting"),
        StylePreset(id: "watercolor", name: "Watercolor", category: .art,
                    style: "delicate watercolor illustration, soft washes, textured paper, loose ink outlines"),
        StylePreset(id: "clay", name: "Clay", category: .art,
                    style: "claymation style, handmade plasticine figures, soft studio lighting, stop-motion miniature set"),
        StylePreset(id: "anime", name: "Anime", category: .art,
                    style: "anime key visual, cel shading, vibrant colors, detailed painted background")
    ]
}
