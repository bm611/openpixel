import SwiftUI

struct ModelsView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A model for your imagination.")
                        .font(.system(size: 25, weight: .medium, design: .serif))
                    Text("Download once. Create offline, whenever you like.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                    .accessibilityLabel("Close model library")
                    .keyboardShortcut(.escape, modifiers: [])
            }

            ForEach(store.catalog) { model in
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        Image(systemName: "cube.transparent.fill")
                            .font(.system(size: 30)).foregroundStyle(Palette.accent)
                            .frame(width: 48, height: 48)
                            .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name).font(.title3.weight(.semibold))
                            Text(model.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.isInstalled ? "READY" : "RECOMMENDED")
                            .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                            .foregroundStyle(store.isInstalled ? .green : Palette.accent)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.035), in: Capsule())
                    }
                    Text(model.description).font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 18) {
                        Label(model.downloadSize, systemImage: "internaldrive")
                        Label(model.license, systemImage: "doc.text")
                        Spacer()
                        Link("Model card ↗", destination: model.sourceURL)
                    }.font(.caption).foregroundStyle(.secondary)
                    if store.memoryGB < model.recommendedMemoryGB {
                        Label("Your Mac has \(store.memoryGB) GB of memory. This model may run slowly or fail to fit.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Divider()
                    if store.operation == .downloading {
                        VStack(alignment: .leading, spacing: 10) {
                            if let progress = store.progress {
                                ProgressView(value: progress)
                            } else { ProgressView().controlSize(.small) }
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(store.status).lineLimit(1)
                                    if let detail = store.downloadDetail {
                                        Text(detail).foregroundStyle(.secondary)
                                    }
                                }.font(.caption)
                                Spacer()
                                Button("Cancel") { store.cancel() }
                            }
                        }
                    } else {
                        HStack {
                            if store.isInstalled {
                                Label("Available offline", systemImage: "checkmark.circle.fill")
                                    .font(.callout).foregroundStyle(.secondary)
                                Spacer()
                                Button("Remove…", role: .destructive) { confirmRemoval = true }
                                    .disabled(store.operation.isBusy)
                            } else {
                                Text("Weights from Hugging Face")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    store.selectedModelID = model.id
                                    store.download()
                                } label: {
                                    Label(store.modelStatuses.first { $0.id == model.id }?.partial == true ? "Resume Download" : "Download \(model.downloadSize)", systemImage: "arrow.down")
                                }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(store.operation.isBusy)
                            }
                        }
                    }
                }
                .padding(20)
                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "lock.shield")
                Text("Only model downloads use the internet. Prompts and generated images are processed and stored on this Mac.")
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Show storage folder") { NSWorkspace.shared.open(store.paths.root) }
                    .buttonStyle(.link).font(.caption)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560)
        .tint(Palette.accent)
        .confirmationDialog("Remove the downloaded model?", isPresented: $confirmRemoval) {
            Button("Remove model", role: .destructive) { store.removeModel() }
        } message: {
            Text("This frees up \(store.selectedModel?.downloadSize ?? "disk space"). Your generated images stay in your library. You can download the model again later.")
        }
    }
}

struct ImageInfoView: View {
    let image: GeneratedImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Behind the image").font(.title2.weight(.medium))
            ScrollView {
                Text(image.prompt).font(.body).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 180)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                row("Model", image.modelName)
                row("Dimensions", image.dimensions)
                row("Seed", String(image.seed))
                row("Steps", String(image.steps))
                row("Generation", "\(image.durationSeconds.formatted()) seconds")
                row("Model revision", String(image.modelRevision.prefix(12)))
                row("Runtime", "mflux \(image.runtimeVersion)")
            }.font(.callout).textSelection(.enabled)
            Text("The PNG also contains these settings, so they travel with your exported image.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(28).frame(width: 470)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
