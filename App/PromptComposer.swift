import SwiftUI

/// The prompt box: a roomy writing area with style, shape, settings, and model below it.
struct PromptComposer: View {
    @Bindable var store: AppStore
    @FocusState private var focused: Bool
    @State private var showStylePicker = false
    @State private var showModelPicker = false
    @State private var showShapePicker = false
    @State private var showSettings = false

    private let limit = 4000
    private var tooLong: Bool { store.prompt.count > limit }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if store.prompt.isEmpty {
                    Text(store.preset.map { "Describe your image in \($0.name.lowercased()) style" }
                         ?? "Describe your image")
                        .font(.app(16))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $store.prompt)
                    .font(.app(16))
                    .lineSpacing(4)
                    .foregroundStyle(Palette.text)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($focused)
                    .accessibilityLabel("Describe your image")
                    .disabled(store.operation.isBusy)
            }
            .frame(height: 68)
            .overlay(alignment: .topTrailing) {
                if !store.prompt.isEmpty {
                    HStack(spacing: 8) {
                        if store.prompt.count > 3000 {
                            Text("\(store.prompt.count.formatted()) / \(limit.formatted())")
                                .font(.app(11.5)).monospacedDigit()
                                .foregroundStyle(tooLong ? AnyShapeStyle(.red) : AnyShapeStyle(Palette.textTertiary))
                        }
                        Button { store.prompt = "" } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(IconButtonStyle())
                        .foregroundStyle(Palette.textTertiary)
                        .help("Clear prompt")
                        .accessibilityLabel("Clear prompt")
                        .disabled(store.operation.isBusy)
                    }
                    .offset(x: 6, y: -6)
                }
            }
            .padding(.horizontal, 12).padding(.top, 16)

            HStack(spacing: 8) {
                styleChip
                shapeChip
                settingsChip
                Spacer(minLength: 8)
                modelMenu
                action
            }
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 12)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(focused ? Palette.surfaceHighest : Palette.surface, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.18), value: focused)
        .onAppear { focused = true }
    }

    // MARK: Chips

    private var styleChip: some View {
        HStack(spacing: 0) {
            Button { showStylePicker.toggle() } label: {
                HStack(spacing: 7) {
                    if let preset = store.preset, let url = preset.previewURL,
                       let image = ImageCache.thumbnail(at: url, pixels: 400) {
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: 20, height: 20).clipShape(Circle())
                        Text(preset.name)
                        // Room for the clear button overlaid at the capsule's end.
                        Color.clear.frame(width: 16, height: 1)
                    } else {
                        Image(systemName: "paintpalette")
                        Text("Style")
                    }
                }
            }
            .buttonStyle(ChipButtonStyle(selected: store.preset != nil))
            .help("Choose a style preset")
            if store.preset != nil {
                Button { store.presetID = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Palette.onAccentContainer.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.onAccentContainer)
                .padding(.leading, -30).padding(.trailing, 7)
                .help("Remove style")
                .accessibilityLabel("Remove style")
            }
        }
        .disabled(store.operation.isBusy)
        .popover(isPresented: $showStylePicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Style").font(.app(14, .medium))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 8), count: 4), spacing: 8) {
                    ForEach(StylePreset.all) { preset in
                        PresetCard(preset: preset, selected: store.presetID == preset.id,
                                   cornerRadius: 16, labelSize: 11) {
                            store.presetID = store.presetID == preset.id ? nil : preset.id
                            showStylePicker = false
                        }
                    }
                }
                if store.preset != nil {
                    Button { store.presetID = nil; showStylePicker = false } label: {
                        Label("No style", systemImage: "circle.slash")
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
            .padding(14)
        }
    }

    private var shapeChip: some View {
        Button { showShapePicker.toggle() } label: {
            HStack(spacing: 7) {
                ShapeGlyph(ratio: store.aspect, size: 14)
                Text(store.aspect.rawValue)
            }
        }
        .buttonStyle(ChipButtonStyle())
        .disabled(store.operation.isBusy)
        .help("Image shape: \(store.aspect.width) × \(store.aspect.height)")
        .popover(isPresented: $showShapePicker, arrowEdge: .bottom) {
            HStack(spacing: 8) {
                ForEach(AspectRatio.allCases) { ratio in
                    let selected = store.aspect == ratio
                    Button {
                        store.aspect = ratio
                        showShapePicker = false
                    } label: {
                        VStack(spacing: 8) {
                            ShapeGlyph(ratio: ratio, size: 30)
                            VStack(spacing: 1) {
                                Text(ratio.rawValue).font(.app(13, .medium))
                                Text("\(ratio.width) × \(ratio.height)")
                                    .font(.app(11)).monospacedDigit()
                                    .opacity(0.7)
                            }
                        }
                        .foregroundStyle(selected ? Palette.onAccentContainer : Palette.text)
                        .frame(width: 92, height: 94)
                        .background(selected ? Palette.accentContainer : Palette.surfaceHigh,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(ratio.rawValue), \(ratio.width) by \(ratio.height)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(12)
        }
    }

    private var settingsChip: some View {
        Button { showSettings.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: "slider.horizontal.3")
                Text(settingsSummary).monospacedDigit()
            }
        }
        .buttonStyle(ChipButtonStyle())
        .disabled(store.operation.isBusy)
        .help("Steps and seed")
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Steps").font(.app(13, .medium))
                        Spacer()
                        Text("\(store.steps)").font(.app(13)).monospacedDigit().foregroundStyle(Palette.textSecondary)
                    }
                    Slider(value: Binding(get: { Double(store.steps) }, set: { store.steps = Int($0.rounded()) }),
                           in: 1...8, step: 1)
                    Text("More steps can add detail but take longer. \(store.selectedModel.map { "\($0.name) is tuned for \($0.defaultSteps)." } ?? "")")
                        .font(.app(12)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seed").font(.app(13, .medium))
                    HStack(spacing: 6) {
                        TextField("Random", text: $store.seedText)
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .accessibilityLabel("Seed, empty for random")
                        Button { store.seedText = String(UInt32.random(in: 0...UInt32.max)) } label: {
                            Image(systemName: "dice")
                        }
                        .help("Pick a random seed")
                        .accessibilityLabel("Pick a random seed")
                        if !store.seedText.isEmpty {
                            Button { store.seedText = "" } label: { Image(systemName: "xmark") }
                                .help("Use a new random seed each time")
                                .accessibilityLabel("Clear seed")
                        }
                    }
                    .buttonStyle(IconButtonStyle())
                    Text("Reuse a seed and prompt to revisit an idea.")
                        .font(.app(12)).foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(16)
            .frame(width: 280)
        }
    }

    private var settingsSummary: String {
        let seed = store.seedText.trimmingCharacters(in: .whitespaces)
        return "\(store.steps) steps" + (seed.isEmpty ? "" : " · Seed \(seed)")
    }

    private var modelMenu: some View {
        Button { showModelPicker.toggle() } label: {
            HStack(spacing: 6) {
                Text(store.selectedModel?.name ?? "Model")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.app(13, .medium))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 8)
        }
        .buttonStyle(IconButtonStyle())
        .disabled(store.operation.isBusy)
        .help("Choose a model")
        .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(store.catalog) { model in
                    let installed = store.isInstalled(model)
                    Button {
                        showModelPicker = false
                        if installed { store.select(model) } else { store.showModels = true }
                    } label: {
                        HStack(spacing: 10) {
                            ModelGlyph(modelID: model.id, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.name).font(.app(13.5, .medium))
                                Text(installed ? model.subtitle : "Not downloaded · \(model.downloadSize)")
                                    .font(.app(12)).foregroundStyle(Palette.textTertiary)
                            }
                            Spacer(minLength: 16)
                            if model.id == store.selectedModelID {
                                Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                            } else if !installed {
                                Image(systemName: "arrow.down.circle").foregroundStyle(Palette.textTertiary)
                            }
                        }
                        .opacity(installed ? 1 : 0.6)
                    }
                    .buttonStyle(RowButtonStyle())
                }
                Divider().padding(.vertical, 4)
                Button {
                    showModelPicker = false
                    store.showModels = true
                } label: {
                    Label("Manage models…", systemImage: "square.grid.2x2")
                }
                .buttonStyle(RowButtonStyle())
            }
            .padding(8)
            .frame(width: 310)
        }
    }

    // MARK: Action

    @ViewBuilder
    private var action: some View {
        if store.operation.canCancel {
            Button { store.cancel() } label: {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Cancel")
                }
            }
            .buttonStyle(ChipButtonStyle())
        } else if !store.isInstalled {
            Button { store.showModels = true } label: {
                Label("Get model", systemImage: "arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.operation.isBusy)
        } else {
            Button { store.generate() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkle")
                    Text("Generate")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!store.canGenerate || tooLong)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Generate image (⌘Return)")
        }
    }
}
