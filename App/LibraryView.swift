import SwiftUI

struct LibraryView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var sort: Sort = .newest

    enum Sort: String, CaseIterable, Identifiable {
        case newest = "Newest first"
        case oldest = "Oldest first"
        case prompt = "Prompt A–Z"
        case model = "Model"

        var id: String { rawValue }
    }

    private var images: [GeneratedImage] {
        switch sort {
        case .newest: store.history.sorted { $0.createdAt > $1.createdAt }
        case .oldest: store.history.sorted { $0.createdAt < $1.createdAt }
        case .prompt: store.history.sorted { $0.prompt.localizedCaseInsensitiveCompare($1.prompt) == .orderedAscending }
        case .model:
            store.history.sorted {
                $0.modelName == $1.modelName ? $0.createdAt > $1.createdAt : $0.modelName < $1.modelName
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 28, weight: .light))
                    Text("Images you create appear here.")
                }
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(images) { image in
                            LibraryThumbnail(image: image, selected: store.selection?.id == image.id) {
                                store.selection = image
                                dismiss()
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 780, height: 700)
        .background(Palette.background)
        .font(.app(13))
        .foregroundStyle(Palette.text)
        .tint(Palette.accent)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Library").font(.display(28))
                Text(store.history.count == 1 ? "1 image" : "\(store.history.count) images")
                    .font(.app(14)).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            Picker("Sort by", selection: $sort) {
                ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            Button { store.openLibrary() } label: { Image(systemName: "folder") }
                .buttonStyle(IconButtonStyle())
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .overlay(alignment: .bottom) { Divider() }
    }
}
