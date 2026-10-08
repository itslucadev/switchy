import Foundation

final class Search {
    private static var preparedCache: SearchTestable.PreparedQuery?

    static func preparedQuery(_ query: String) -> SearchTestable.PreparedQuery {
        if let cached = preparedCache, cached.original == query { return cached }
        let prepared = SearchTestable.PreparedQuery(query)
        preparedCache = prepared
        return prepared
    }

    static func normalizedQuery(_ query: String) -> String {
        preparedQuery(query).normalized.text
    }

    static func result(for window: Window, query: SearchTestable.PreparedQuery) -> (
        matches: Bool, relevance: Double
    ) {
        if query.normalized.text.isEmpty { return (true, 0) }
        ensureCache(for: window, query: query)
        return (window.swBestSimilarity > 0, window.swBestSimilarity)
    }

    private static func ensureCache(for window: Window, query: SearchTestable.PreparedQuery) {
        let cacheKey = query.original + "|3"
        if window.lastSearchQuery == cacheKey { return }
        let appName = window.application.localizedName ?? ""
        let title = window.title
        let appResult = SearchTestable.tierMatch(query: query, text: appName)
        let titleResult = SearchTestable.tierMatch(query: query, text: title)
        window.swAppResults = appResult.map { [$0.toSWResult()] } ?? []
        window.swTitleResults = titleResult.map { [$0.toSWResult()] } ?? []
        let appScore = Double(appResult?.score ?? 0)
        let titleScore = Double(titleResult?.score ?? 0)
        window.swBestSimilarity = max(appScore * 1.02, titleScore)
        window.lastSearchQuery = cacheKey
    }
}
