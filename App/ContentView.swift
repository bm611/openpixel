import AppKit
import SwiftUI

enum Palette {
    static let accent = Color(red: 0.82, green: 0.32, blue: 0.20)
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let line = Color.primary.opacity(0.08)
}

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 238)
            Divider()
            VStack(spacing: 18) {
                header
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !store.history.isEmpty { historyStrip }
                composer
            }
            .padding(24)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                PixelMark(size: 30)
                Text("OpenPixel").font(.system(size: 21, weight: .semibold, design: .rounded))
            }
            .padding(.top, 44)

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("MODEL")
                HStack(spacing: 10) {
                    Image(systemName: "cube.transparent")
                        .font(.title2).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.selectedModel?.name ?? "Loading…").font(.headline)
                        Text(store.isInstalled ? "Downloaded · 4-bit" : "Download to get started")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button { store.showModels = true } label: {
                    HStack {
                        Text("Manage models")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("IMAGE SHAPE")
                HStack(spacing: 8) {
                    ForEach(AspectRatio.allCases) { ratio in
                        Button {
                            store.aspect = ratio
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: ratio.symbol).font(.system(size: 20, weight: .light))
                                    .frame(height: 24)
                                Text(ratio.rawValue).font(.system(size: 10, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(store.aspect == ratio ? Palette.accent.opacity(0.10) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(store.aspect == ratio ? Palette.accent.opacity(0.65) : Color.clear))
                            .foregroundStyle(store.aspect == ratio ? Palette.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(ratio.rawValue), \(ratio.width) by \(ratio.height)")
                        .accessibilityAddTraits(store.aspect == ratio ? .isSelected : [])
                    }
                }
                Text("\(store.aspect.width) × \(store.aspect.height) pixels")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .disabled(store.operation.isBusy)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 16) {
                    Stepper("Steps: \(store.steps)", value: $store.steps, in: 1...8)
                        .font(.callout)
                    Text("4 steps is the recommended default.")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Seed").font(.callout)
                        TextField("Random", text: $store.seedText)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Seed, empty for random")
                        Text("Reuse a seed and prompt to revisit an idea.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 12)
            } label: {
                Text("Advanced").font(.callout).foregroundStyle(.secondary)
            }
            .disabled(store.operation.isBusy)

            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 8) {
                Label("Made on your Mac", systemImage: "desktopcomputer")
                    .font(.callout.weight(.medium))
                Text("Your prompts and images stay here.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Apple Silicon · \(store.memoryGB) GB memory")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your next idea, in pixels.")
                    .font(.system(size: 23, weight: .medium, design: .serif))
                Text("A small studio for a big imagination.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.newImage() } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New image (⌘N)")
            .accessibilityLabel("New image")
            .disabled(store.operation.isBusy)
            Button { store.openLibrary() } label: { Image(systemName: "folder") }
                .help("Open image library")
                .accessibilityLabel("Open image library")
        }
        .buttonStyle(.borderless)
        .controlSize(.large)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Palette.canvas)
            if let image = store.selection, let nsImage = NSImage(contentsOf: image.url) {
                VStack(spacing: 0) {
                    Image(nsImage: nsImage)
                        .resizable().scaledToFit()
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(image.prompt)
                    HStack(spacing: 12) {
                        Text(image.dimensions).monospacedDigit()
                        Text("·")
                        Text("\(Int(image.durationSeconds))s")
                        Spacer()
                        Button { store.reuse(image) } label: { Image(systemName: "arrow.uturn.backward") }
                            .help("Reuse prompt and settings").accessibilityLabel("Reuse prompt and settings")
                            .disabled(store.operation.isBusy)
                        Button { store.showImageInfo = true } label: { Image(systemName: "info.circle") }
                            .help("Image details").accessibilityLabel("Image details")
                        Button { store.revealImage() } label: { Image(systemName: "folder") }
                            .help("Reveal in Finder").accessibilityLabel("Reveal in Finder")
                        Button { store.saveImage() } label: { Label("Save As", systemImage: "square.and.arrow.up") }
                            .help("Save image as… (⌘S)")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Color.primary.opacity(0.025))
                }
            } else {
                emptyState
            }
            if store.operation == .generating || store.operation == .cancelling {
                RoundedRectangle(cornerRadius: 16).fill(.regularMaterial)
                VStack(spacing: 14) {
                    ProgressView().controlSize(.regular)
                    Text(store.status).font(.headline)
                    if let progress = store.progress {
                        ProgressView(value: progress).frame(width: 220)
                    }
                    Text("Working locally on your Mac")
                        .font(.caption).foregroundStyle(.secondary)
                    if store.operation.canCancel {
                        Button("Cancel") { store.cancel() }.buttonStyle(.bordered)
                    }
                }
                .padding(24)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            PixelMark(size: 62).opacity(0.8)
                .padding(.bottom, 6)
            Text(store.isInstalled ? "Start with a little imagination." : "Your own image studio.")
                .font(.system(size: 22, weight: .medium, design: .serif))
            Text(store.isInstalled
                 ? "Describe a scene, a feeling, or something that doesn't exist yet."
                 : "Download a model once. Create on your Mac, even offline.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
            if !store.isInstalled {
                Button { store.showModels = true } label: {
                    Label("Set up your model", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .padding(.top, 6)
            } else {
                Button("Try a quiet mountain landscape ↗") {
                    store.prompt = "A quiet mountain lake at dawn, pale mist over still water, tiny pine trees along the shore, soft film grain, muted earth tones, medium format landscape photography."
                }
                .buttonStyle(.plain).foregroundStyle(Palette.accent)
                .font(.callout).padding(.top, 6)
            }
        }
        .padding(28)
    }

    private var historyStrip: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("RECENT").font(.system(size: 9, weight: .semibold)).tracking(1)
                Text(store.history.count == 1 ? "1 image" : "\(store.history.count) images")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(store.history) { image in
                        Button { store.selection = image } label: {
                            if let thumbnail = NSImage(contentsOf: image.url) {
                                Image(nsImage: thumbnail).resizable().scaledToFill()
                                    .frame(width: 54, height: 54).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    .padding(3)
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(store.selection?.id == image.id ? Palette.accent : .clear, lineWidth: 1.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(image.prompt)
                        .help(image.prompt)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: 60)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DESCRIBE YOUR IMAGE")
                    .font(.system(size: 10, weight: .semibold)).tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.prompt.isEmpty {
                    Text("\(store.prompt.count)/4000")
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(store.prompt.count > 4000 ? .red : .secondary)
                }
            }
            ZStack(alignment: .topLeading) {
                if store.prompt.isEmpty {
                    Text("A sunlit room, a strange little creature, a place you've never been…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5).padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $store.prompt)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 14))
                    .frame(height: 74)
                    .accessibilityLabel("Describe your image")
                    .disabled(store.operation.isBusy)
            }
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle().fill(store.operation.isBusy ? Palette.accent : Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text(store.status).lineLimit(1)
                }
                .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if store.operation.canCancel {
                    Button("Cancel") { store.cancel() }.controlSize(.large)
                } else {
                    Button { store.generate() } label: {
                        HStack(spacing: 8) {
                            Text("Generate")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!store.canGenerate || store.prompt.count > 4000)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Generate image (⌘Return)")
                }
            }
        }
        .padding(17)
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .tracking(1).foregroundStyle(.tertiary)
    }
}

struct PixelMark: View {
    var size: CGFloat = 32
    private let pixels: [Double] = [0.25, 0.7, 0, 0.7, 1, 0.65, 0, 0.65, 0.25]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: size * 0.09), count: 3), spacing: size * 0.09) {
            ForEach(0..<9) { index in
                RoundedRectangle(cornerRadius: size * 0.035)
                    .fill(Palette.accent.opacity(pixels[index]))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
