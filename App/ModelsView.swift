import SwiftUI

struct ModelsView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRemoval: ModelInfo?

    /// Labs in catalog order, so the recommended model's lab comes first.
    private var labs: [String] {
        store.catalog.reduce(into: []) { if !$0.contains($1.lab) { $0.append($1.lab) } }
    }

    private var installedBytes: Int64 {
        store.installedModels.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(labs, id: \.self) { lab in
                        let models = store.catalog.filter { $0.lab == lab }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(lab).font(.display(20))
                                Text(models.count == 1 ? "1 model" : "\(models.count) models")
                                    .font(.app(12))
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                                      alignment: .leading, spacing: 16) {
                                ForEach(models) { model in
                                    ModelCard(store: store, model: model) { pendingRemoval = model }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            footer
        }
        .frame(width: 780, height: 700)
        .background(Palette.background)
        .font(.app(13))
        .foregroundStyle(Palette.text)
        .tint(Palette.accent)
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "this model")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { model in
            Button("Remove model", role: .destructive) { store.removeModel(model) }
        } message: { model in
            Text("This frees up \(model.downloadSize). Your generated images stay in your library. You can download the model again later.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            PixelMark(size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("Models").font(.display(28))
                Text("Download once. Create offline, whenever you like.")
                    .font(.app(14)).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(store.installedModels.count) of \(store.catalog.count) downloaded")
                    .font(.app(12, .medium))
                Text("\(ByteCountFormatter.string(fromByteCount: installedBytes, countStyle: .file)) on disk · \(store.memoryGB) GB memory")
                    .font(.app(12)).foregroundStyle(Palette.textTertiary)
            }
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle())
                .foregroundStyle(Palette.textTertiary)
                .accessibilityLabel("Close model library")
                .keyboardShortcut(.escape, modifiers: [])
                .padding(.leading, 6)
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.shield")
            Text("Only model downloads use the internet. Prompts and images stay on this Mac.")
            Spacer()
            Button("Show storage folder") { NSWorkspace.shared.open(store.paths.root) }
                .buttonStyle(ChipButtonStyle())
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.leading, 8)
        }
        .font(.app(12)).foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, 24).padding(.vertical, 14)
    }
}

private struct ModelCard: View {
    @Bindable var store: AppStore
    let model: ModelInfo
    let onRemove: () -> Void
    @State private var hovering = false

    private var tint: Color { Palette.tint(for: model.id) }
    private var installed: Bool { store.isInstalled(model) }
    private var selected: Bool { store.selectedModelID == model.id && installed }
    private var isBusyHere: Bool { store.busyModelID == model.id && store.operation.isBusy }
    private var lowMemory: Bool { store.memoryGB < model.recommendedMemoryGB }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name).font(.display(20))
                    Text(model.subtitle).font(.app(12)).foregroundStyle(Palette.textTertiary)
                }
                Text(model.description)
                    .font(.app(12.5)).foregroundStyle(Palette.textTertiary)
                    .lineLimit(3, reservesSpace: true)
                specs
                if lowMemory {
                    Label("Needs about \(model.recommendedMemoryGB) GB of memory. Your Mac has \(store.memoryGB) GB, so this may be slow or fail to load.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.app(12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                actions
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(selected ? tint.opacity(0.7) : Palette.line, lineWidth: selected ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.10 : 0.04), radius: hovering ? 14 : 6, y: hovering ? 6 : 2)
        .offset(y: hovering ? -2 : 0)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }

    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            tint.opacity(0.12)
            PixelArt(seed: model.id, tint: tint, cell: 13)
            HStack {
                if let badge = model.badge { Pill(text: badge, tint: tint) }
                Spacer()
                if selected {
                    Label("In use", systemImage: "checkmark.circle.fill")
                        .font(.app(11, .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                } else if installed {
                    Label("Downloaded", systemImage: "checkmark")
                        .font(.app(11, .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .padding(12)
        }
        .frame(height: 96)
        .clipped()
    }

    private var specs: some View {
        HStack(spacing: 0) {
            spec("internaldrive", model.downloadSize, "Download size")
            spec("memorychip", "\(model.recommendedMemoryGB) GB+", "Recommended memory")
            spec("bolt", "\(model.defaultSteps) steps", "Default steps")
            spec(model.isNonCommercial ? "exclamationmark.shield" : "checkmark.seal",
                 model.isNonCommercial ? "Non-comm." : model.license, "License: \(model.license)")
        }
        .padding(.vertical, 8)
        .background(Palette.surfaceHigh, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func spec(_ symbol: String, _ value: String, _ help: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.app(11)).foregroundStyle(Palette.textTertiary)
            Text(value).font(.app(11, .medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(help): \(value)")
    }

    @ViewBuilder
    private var actions: some View {
        if isBusyHere && store.operation == .downloading {
            VStack(alignment: .leading, spacing: 8) {
                if let progress = store.progress {
                    ProgressView(value: progress).tint(tint)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(tint)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.status).lineLimit(1)
                        if let detail = store.downloadDetail {
                            Text(detail).monospacedDigit().foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .font(.app(12))
                    Spacer()
                    Button("Cancel") { store.cancel() }
                        .buttonStyle(ChipButtonStyle())
                }
            }
        } else if isBusyHere && store.operation == .removing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Removing…").font(.app(12)).foregroundStyle(Palette.textTertiary)
            }
            .frame(height: 34)
        } else if installed {
            HStack(spacing: 8) {
                if selected {
                    Label("Ready to create", systemImage: "checkmark.circle.fill")
                        .font(.app(12, .medium))
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    Button { store.select(model) } label: { Text("Use this model") }
                        .buttonStyle(PrimaryButtonStyle(tint: tint, foreground: Palette.hex(0x131314)))
                        .disabled(store.operation.isBusy)
                }
                Spacer()
                Link(destination: model.sourceURL) { Image(systemName: "arrow.up.right.square") }
                    .foregroundStyle(Palette.textTertiary)
                    .help("Open model card")
                Button(action: onRemove) { Image(systemName: "trash") }
                    .buttonStyle(IconButtonStyle())
                    .foregroundStyle(Palette.textTertiary)
                    .disabled(store.operation.isBusy)
                    .help("Remove model")
                    .accessibilityLabel("Remove \(model.name)")
            }
            .frame(height: 34)
        } else {
            HStack(spacing: 8) {
                Button { store.download(model) } label: {
                    Label(store.hasPartialDownload(model) ? "Resume download" : "Download · \(model.downloadSize)",
                          systemImage: "arrow.down")
                }
                .buttonStyle(PrimaryButtonStyle(tint: tint, foreground: Palette.hex(0x131314)))
                .disabled(store.operation.isBusy)
                Spacer()
                Link("Model card ↗", destination: model.sourceURL)
                    .font(.app(12))
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(height: 34)
        }
    }
}

struct ImageInfoView: View {
    let image: GeneratedImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                if let thumbnail = ImageCache.thumbnail(at: image.url) {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Behind the image").font(.display(22))
                    Text(image.modelName).font(.app(12)).foregroundStyle(Palette.textTertiary)
                }
            }
            ScrollView {
                Text(image.prompt).font(.app(14)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 160)
            .background(Palette.surfaceHigh, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                row("Model", image.modelName)
                row("Dimensions", image.dimensions)
                row("Seed", String(image.seed))
                row("Steps", String(image.steps))
                row("Generation", "\(image.durationSeconds.formatted()) seconds")
                row("Model revision", String(image.modelRevision.prefix(12)))
                row("Runtime", "mflux \(image.runtimeVersion)")
            }.font(.app(14)).textSelection(.enabled)
            Text("The PNG also contains these settings, so they travel with your exported image.")
                .font(.app(12)).foregroundStyle(Palette.textTertiary)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 470)
        .font(.app(13))
        .foregroundStyle(Palette.text)
        .background(Palette.background)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(Palette.textTertiary)
            Text(value).monospacedDigit()
        }
    }
}
