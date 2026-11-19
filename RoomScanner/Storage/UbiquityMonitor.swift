import Foundation

/// iCloud state of `.roomscan` package, derived from `NSMetadataItem` attributes.
struct CloudItemStatus: Equatable {
    enum Download: Equatable { case current, downloaded, notDownloaded }
    var url: URL
    var download: Download
    var isDownloading: Bool
    var isUploading: Bool
    var isUploaded: Bool
    var percentDownloaded: Double
    var hasUnresolvedConflicts: Bool

    /// Is the package readable locally?
    var isAvailableLocally: Bool { download != .notDownloaded }

    init(url: URL, download: Download = .current, isDownloading: Bool = false, isUploading: Bool = false, isUploaded: Bool = true, percentDownloaded: Double = 100, hasUnresolvedConflicts: Bool = false) {
        self.url = url; self.download = download; self.isDownloading = isDownloading; self.isUploading = isUploading
        self.isUploaded = isUploaded; self.percentDownloaded = percentDownloaded; self.hasUnresolvedConflicts = hasUnresolvedConflicts
    }

    /// From attribute dictionary (`NSMetadataItem.values(forAttributes:)`), testable without iCloud.
    init?(attributes a: [String: Any]) {
        guard let url = a[NSMetadataItemURLKey] as? URL else { return nil }
        let status = a[NSMetadataUbiquitousItemDownloadingStatusKey] as? String
        let download: Download = switch status {
        case NSMetadataUbiquitousItemDownloadingStatusCurrent?: .current
        case NSMetadataUbiquitousItemDownloadingStatusDownloaded?: .downloaded
        case NSMetadataUbiquitousItemDownloadingStatusNotDownloaded?: .notDownloaded
        default: .current
        }
        self.init(url: url, download: download,
                  isDownloading: a[NSMetadataUbiquitousItemIsDownloadingKey] as? Bool ?? false,
                  isUploading: a[NSMetadataUbiquitousItemIsUploadingKey] as? Bool ?? false,
                  isUploaded: a[NSMetadataUbiquitousItemIsUploadedKey] as? Bool ?? true,
                  percentDownloaded: a[NSMetadataUbiquitousItemPercentDownloadedKey] as? Double ?? (download == .notDownloaded ? 0 : 100),
                  hasUnresolvedConflicts: a[NSMetadataUbiquitousItemHasUnresolvedConflictsKey] as? Bool ?? false)
    }

    static let attributeKeys: [String] = [
        NSMetadataItemURLKey, NSMetadataUbiquitousItemDownloadingStatusKey, NSMetadataUbiquitousItemIsDownloadingKey,
        NSMetadataUbiquitousItemIsUploadingKey, NSMetadataUbiquitousItemIsUploadedKey,
        NSMetadataUbiquitousItemPercentDownloadedKey, NSMetadataUbiquitousItemHasUnresolvedConflictsKey,
    ]
}

/// Continuously monitors `.roomscan` and `.housescan` in iCloud container (`NSMetadataQuery`) and
/// triggers background download for packages not yet on device.
@MainActor
final class UbiquityMonitor {
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private(set) var items: [CloudItemStatus] = []
    var onChange: (([CloudItemStatus]) -> Void)?

    init() {
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE %@ OR %K LIKE %@", NSMetadataItemFSNameKey, "*.\(FileLayout.packageExtension)", NSMetadataItemFSNameKey, "*.\(FileLayout.housePackageExtension)")
        query.notificationBatchingInterval = 0.5
    }

    func start() {
        guard observers.isEmpty else { return }
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        query.start()
    }

    func stop() {
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    deinit {
        // Store may be released without `stop()` (window closed): query must not outlive it.
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func refresh() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var statuses: [CloudItemStatus] = []
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            if let s = CloudItemStatus(attributes: item.values(forAttributes: CloudItemStatus.attributeKeys) ?? [:]) { statuses.append(s) }
        }
        items = statuses
        for s in statuses where s.download == .notDownloaded && !s.isDownloading {
            try? FileManager.default.startDownloadingUbiquitousItem(at: s.url)
        }
        onChange?(statuses)
    }
}
