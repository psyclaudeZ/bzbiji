import SwiftUI

// MARK: - Model

private let imageExts = Set(["png", "jpg", "jpeg", "webp", "gif", "tiff", "heic"])
private let supportedExts = imageExts.union(["md", "markdown"])

struct BrowserItem: Identifiable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let thumbnail: NSImage?   // nil for non-images

    var name: String { url.lastPathComponent }
    var ext: String { url.pathExtension.lowercased() }
    var isImage: Bool { imageExts.contains(ext) }
    var isMarkdown: Bool { ext == "md" || ext == "markdown" }
}

// MARK: - File item view

private struct FileItemView: View {
    let item: BrowserItem
    let onNavigate: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            icon
                .frame(width: 52, height: 52)

            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .frame(width: 72)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if item.isDirectory { onNavigate() } }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .help(item.name)
    }

    @ViewBuilder
    private var icon: some View {
        if item.isDirectory {
            Image(systemName: "folder.fill")
                .font(.system(size: 36))
                .foregroundColor(Color(NSColor.systemYellow))
        } else if item.isImage, let thumb = item.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 52, height: 52)
                .clipped()
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        } else {
            // Markdown or other supported file
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                Text("MD")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 52, height: 52)
        }
    }
}

// MARK: - File browser

struct FileBrowser: View {
    @State private var currentDir: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var items: [BrowserItem] = []

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    // Breadcrumb components: (display name, url)
    private var breadcrumbs: [(String, URL)] {
        var result: [(String, URL)] = []
        var url = currentDir.standardized
        let home = Self.home.standardized

        while true {
            if url == home {
                result.insert(("~", home), at: 0)
                break
            }
            if url.pathComponents.count <= 1 {
                result.insert((url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent, url), at: 0)
                break
            }
            result.insert((url.lastPathComponent, url), at: 0)
            url = url.deletingLastPathComponent().standardized
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            fileGrid
        }
        .background(Color(NSColor.underPageBackgroundColor))
        .onAppear { load() }
    }

    // MARK: Breadcrumb

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                // Home shortcut
                Button {
                    navigate(to: Self.home)
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)

                ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { idx, crumb in
                    if idx > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }
                    Button(crumb.0) {
                        navigate(to: crumb.1)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: idx == breadcrumbs.count - 1 ? .semibold : .regular))
                    .foregroundColor(idx == breadcrumbs.count - 1 ? .primary : .secondary)
                }

                // Up button
                if currentDir.standardized != Self.home.standardized {
                    Button {
                        navigate(to: currentDir.deletingLastPathComponent())
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }

    // MARK: Grid

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 4)]

    private var fileGrid: some View {
        Group {
            if items.isEmpty {
                Text("No supported files here")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(items) { item in
                            FileItemView(item: item) { navigate(to: item.url) }
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    // MARK: Navigation & loading

    private func navigate(to url: URL) {
        currentDir = url.standardized
        load()
    }

    private func load() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: currentDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { items = []; return }

        var result: [BrowserItem] = []
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let ext = url.pathExtension.lowercased()

            if !isDir && !supportedExts.contains(ext) { continue }

            var thumb: NSImage? = nil
            if imageExts.contains(ext) {
                // Load a small thumbnail
                if let src = NSImage(contentsOf: url) {
                    thumb = src.resized(to: NSSize(width: 104, height: 104))
                }
            }

            result.append(BrowserItem(url: url, isDirectory: isDir, thumbnail: thumb))
        }

        items = result.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - NSImage resize helper

private extension NSImage {
    func resized(to size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        draw(in: NSRect(origin: .zero, size: size),
             from: NSRect(origin: .zero, size: self.size),
             operation: .copy, fraction: 1)
        img.unlockFocus()
        return img
    }
}
