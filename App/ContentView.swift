import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(store: store)
                .frame(width: 260)
            VStack(spacing: 12) {
                topBar
                ImageStage(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                PromptComposer(store: store)
                    .frame(maxWidth: 820)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
        }
        .font(.app(13))
        .foregroundStyle(Palette.text)
        .sheet(isPresented: $store.showModels) { ModelsView(store: store) }
        .sheet(isPresented: $store.showImageInfo) {
            if let image = store.selection { ImageInfoView(image: image) }
        }
        .alert("Something needs attention", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
            Button("Open Logs") { store.openLogs() }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.operation.isBusy ? Palette.accent : Palette.hex(0x5BB974))
                    .frame(width: 7, height: 7)
                Text(store.status).lineLimit(1)
            }
            .font(.app(12.5, .medium))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Palette.surface, in: Capsule())
            .animation(.easeOut(duration: 0.2), value: store.status)
            Spacer()
            Button { store.newImage() } label: { Image(systemName: "square.and.pencil") }
                .help("New image (⌘N)")
                .accessibilityLabel("New image")
                .disabled(store.operation.isBusy)
            Button { store.openLibrary() } label: { Image(systemName: "folder") }
                .help("Open image library")
                .accessibilityLabel("Open image library")
        }
        .buttonStyle(IconButtonStyle())
        .foregroundStyle(Palette.textSecondary)
        .frame(height: 32)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                PixelMark(size: 24)
                Text("OpenPixel").font(.app(20, .medium))
            }
            .padding(.leading, 6)
            .padding(.top, 48)
            .padding(.bottom, 20)

            Button { store.newImage() } label: {
                Label("New image", systemImage: "plus")
            }
            .buttonStyle(ChipButtonStyle())
            .disabled(store.operation.isBusy)
            .padding(.bottom, 24)

            sectionTitle("Model")
            modelCard.padding(.bottom, 24)

            HStack {
                sectionTitle("Recent")
                Spacer()
                if !store.history.isEmpty {
                    Text("\(store.history.count)")
                        .font(.app(11, .medium)).monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.bottom, 10)
                }
            }
            library

            privacyNote.padding(.top, 12)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .background(Palette.surface)
    }

    private var modelCard: some View {
        Button { store.showModels = true } label: {
            HStack(spacing: 10) {
                ModelGlyph(modelID: store.selectedModelID, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedModel?.name ?? "Loading…")
                        .font(.app(14, .medium))
                        .lineLimit(1)
                    Text(store.isInstalled
                         ? "\(store.installedModels.count) of \(store.catalog.count) downloaded"
                         : "Not downloaded yet")
                        .font(.app(12))
                        .foregroundStyle(store.isInstalled ? Palette.textTertiary : Palette.accent)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(10)
            .background(Palette.surfaceHigh, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Browse and manage models (⇧⌘M)")
        .accessibilityLabel("Model: \(store.selectedModel?.name ?? ""). Manage models")
    }

    @ViewBuilder
    private var library: some View {
        if store.history.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 20, weight: .light))
                Text("Images you create appear here.")
                    .font(.app(12))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                          spacing: 8) {
                    ForEach(store.history) { image in
                        LibraryThumbnail(image: image, selected: store.selection?.id == image.id) {
                            store.selection = image
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Made on your Mac").font(.app(12.5, .medium))
                Text("Apple Silicon · \(store.memoryGB) GB memory")
                    .font(.app(11)).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.leading, 6)
        .help("Your prompts and images stay on this Mac.")
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.app(12.5, .medium))
            .foregroundStyle(Palette.textSecondary)
            .padding(.leading, 6)
            .padding(.bottom, 10)
    }
}

private struct LibraryThumbnail: View {
    let image: GeneratedImage
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let thumbnail = ImageCache.thumbnail(at: image.url) {
                        Image(nsImage: thumbnail).resizable().scaledToFill()
                    } else {
                        Palette.surfaceHigh
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Palette.accent : .clear, lineWidth: 2.5)
                )
                .scaleEffect(hovering && !selected ? 1.025 : 1)
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(image.prompt)
        .accessibilityLabel(image.prompt)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Stage

private struct ImageStage: View {
    @Bindable var store: AppStore

    var body: some View {
        ZStack {
            if store.operation == .generating || store.operation == .cancelling {
                GeneratingPlaceholder(store: store)
                    .transition(.opacity)
            } else if let image = store.selection, let nsImage = ImageCache.image(at: image.url) {
                VStack(spacing: 14) {
                    Image(nsImage: nsImage)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(image.prompt)
                    imageBar(image)
                        .frame(maxWidth: 820)
                }
                .padding(.top, 8)
                .id(image.id)
                .transition(.opacity)
            } else {
                PresetGallery(store: store)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.selection?.id)
        .animation(.easeOut(duration: 0.25), value: store.operation)
    }

    private func imageBar(_ image: GeneratedImage) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                ModelGlyph(modelID: image.modelID, size: 22)
                Text(image.modelName).font(.app(13, .medium))
                Text("\(image.dimensions)  ·  \(Int(image.durationSeconds.rounded()))s")
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
            }
            .font(.app(13))
            .padding(.leading, 6).padding(.trailing, 14).frame(height: 34)
            .background(Palette.surface, in: Capsule())
            Spacer()
            Button { store.edit(image) } label: {
                Label("Edit", systemImage: "wand.and.stars")
            }
            .buttonStyle(ChipButtonStyle())
            .disabled(store.operation.isBusy)
            .help("Use this image as a reference and describe changes")
            Group {
                Button { store.reuse(image) } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Reuse prompt and settings").accessibilityLabel("Reuse prompt and settings")
                    .disabled(store.operation.isBusy)
                Button { store.showImageInfo = true } label: { Image(systemName: "info.circle") }
                    .help("Image details").accessibilityLabel("Image details")
                Button { store.revealImage() } label: { Image(systemName: "folder") }
                    .help("Reveal in Finder").accessibilityLabel("Reveal in Finder")
            }
            .buttonStyle(IconButtonStyle())
            .foregroundStyle(Palette.textSecondary)
            Button { store.saveImage() } label: {
                Label("Save", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(ChipButtonStyle())
            .help("Save image as… (⌘S)")
        }
    }
}

// MARK: - Generating

/// Holds the image's place while it renders: a shimmering card at the output's
/// proportions, with live progress above it.
private struct GeneratingPlaceholder: View {
    @Bindable var store: AppStore

    var body: some View {
        Color.clear
            .aspectRatio(store.aspect.ratio, contentMode: .fit)
            .overlay { Shimmer() }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .topLeading) {
                header
                    .fixedSize()
                    .alignmentGuide(.top) { $0[.bottom] + 14 }
            }
            .padding(.top, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Creating your image. \(store.status)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            PulsingDots()
            Text(store.status).font(.app(15))
            if let progress = store.progress, store.stage == "generating" {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.app(15)).monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
            }
            if let preset = store.preset {
                Text("· \(preset.name)").font(.app(15)).foregroundStyle(Palette.textTertiary)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.status)
    }
}

/// A soft band of light sweeping diagonally across a neutral surface.
private struct Shimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                Palette.surface
                LinearGradient(colors: [.clear, Palette.shimmer.opacity(0.9), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: width * 0.7)
                    .rotationEffect(.degrees(20))
                    .scaleEffect(y: 2)
                    .offset(x: phase * width * 1.2)
                    .opacity(reduceMotion ? 0 : 1)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}

/// Three dots that pulse in sequence while work is in progress.
private struct PulsingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3) { index in
                    Circle()
                        .frame(width: 5, height: 5)
                        .opacity(0.25 + 0.75 * max(0, sin(time * 5 - Double(index) * 0.9)))
                }
            }
        }
        .foregroundStyle(Palette.text)
        .accessibilityHidden(true)
    }
}

// MARK: - Presets

private struct PresetGallery: View {
    @Bindable var store: AppStore
    @State private var category: StylePreset.Category = .all

    private var presets: [StylePreset] {
        category == .all ? StylePreset.all : StylePreset.all.filter { $0.category == category }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Text(store.isInstalled ? "What will you create?" : "Your own image studio.")
                        .font(.display(38))
                        .foregroundStyle(Palette.text)
                    Text(store.isInstalled
                         ? "Pick a style, then describe your idea below."
                         : "Download a model once, then create on your Mac, even offline.")
                        .font(.app(15))
                        .foregroundStyle(Palette.textTertiary)
                    if !store.isInstalled {
                        Button { store.showModels = true } label: {
                            Label("Browse models", systemImage: "square.grid.2x2")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 8)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.top, 20)

                HStack(spacing: 8) {
                    ForEach(StylePreset.Category.allCases) { item in
                        Button(item.rawValue) { category = item }
                            .buttonStyle(ChipButtonStyle(selected: category == item))
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(presets) { preset in
                        PresetCard(preset: preset, selected: store.presetID == preset.id) {
                            store.presetID = store.presetID == preset.id ? nil : preset.id
                        }
                    }
                }
                .frame(maxWidth: 680)
                .animation(.easeOut(duration: 0.2), value: category)
            }
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

struct PresetCard: View {
    let preset: StylePreset
    let selected: Bool
    var cornerRadius: CGFloat = 26
    var labelSize: CGFloat = 14
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let url = preset.previewURL, let image = ImageCache.thumbnail(at: url, pixels: 400) {
                        Image(nsImage: image).resizable().scaledToFill()
                            .scaleEffect(hovering ? 1.05 : 1)
                    } else {
                        Palette.surfaceHigh
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                        Text(preset.name)
                            .font(.app(labelSize, .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, labelSize * 0.9).padding(.bottom, labelSize * 0.75)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: labelSize * 0.8, weight: .bold))
                            .foregroundStyle(Palette.onAccent)
                            .frame(width: labelSize * 1.7, height: labelSize * 1.7)
                            .background(Palette.accent, in: Circle())
                            .padding(labelSize * 0.7)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(selected ? Palette.accent : .clear, lineWidth: 3)
                )
                .animation(.easeOut(duration: 0.2), value: hovering)
                .animation(.spring(duration: 0.25), value: selected)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(preset.style)
        .accessibilityLabel("\(preset.name) style")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
