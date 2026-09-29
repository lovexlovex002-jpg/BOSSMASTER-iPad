import Foundation

struct NativeFetchEngine {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 35
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1"]
        session = URLSession(configuration: config)
    }
    func search(code: String) async throws -> [SearchRecord] {
        let normalized = code.lowercased()
        let base = SearchModel.sourceBaseURL
        let sources: [(String, String)] = [
            ("Source A", base + "/v/" + normalized),
            ("Source B", base + "/" + normalized + "/")
        ]
        return await withTaskGroup(of: SearchRecord?.self, returning: [SearchRecord].self) { group in
            for (name, raw) in sources {
                if let url = URL(string: raw) {
                    group.addTask { await self.fetchRecord(code: code, source: name, url: url) }
                }
            }
            var out: [SearchRecord] = []
            for await item in group {
                if let item { out.append(item) }
            }
            return out
        }
    }
    func search(urlString: String) async throws -> [SearchRecord] {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { throw FetchError.invalidURL }
        let code = url.lastPathComponent.isEmpty ? (url.host ?? "URL") : url.lastPathComponent.uppercased()
        if let record = await fetchRecord(code: code, source: url.host ?? "URL", url: url) { return [record] }
        return []
    }
    private func fetchRecord(code: String, source: String, url: URL) async -> SearchRecord? {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) else { return nil }
            return HTMLRecordParser.parse(code: code, source: source, url: url, data: data)
        } catch { return nil }
    }
}
enum FetchError: LocalizedError {
    case invalidURL
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "ลิงก์ไม่ถูกต้อง"
        }
    }
}
enum HTMLRecordParser {
    static func parse(code: String, source: String, url: URL, data: Data) -> SearchRecord {
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        var record = SearchRecord(code: code.uppercased(), source: source, pageURL: url)
        record.title = firstMeta(html, keys: ["og:title", "twitter:title"]) ?? firstTitle(html) ?? ""
        record.plot = firstMeta(html, keys: ["og:description", "description"]) ?? ""
        var candidates: [(URL, String)] = []
        if let social = firstMeta(html, keys: ["og:image", "twitter:image"]) {
            if let imageURL = absoluteURL(social, base: url) {
                candidates.append((imageURL, "og-image"))
            }
        }
        candidates += Array(imageSourcesWithHints(html, base: url).prefix(20))
        var seen = Set<URL>()
        for (imageURL, hint) in candidates {
            if seen.insert(imageURL).inserted {
                let role = classifyImage(url: imageURL, hint: hint, isFirst: record.images.isEmpty)
                record.images.append(ImageItem(url: imageURL, role: role))
                if record.images.count >= 11 { break }
            }
        }
        record.actor = firstLabeled(html, labels: ["Actor", "Actress", "Cast"])
        record.studio = firstLabeled(html, labels: ["Studio", "Maker"])
        record.releaseDate = firstLabeled(html, labels: ["Release Date", "Released"])
        record.runtime = firstLabeled(html, labels: ["Runtime", "Duration"])
        return record
    }
    private static func firstMeta(_ html: String, keys: [String]) -> String? {
        for key in keys {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let a = "<meta[^>]+property=[\"']" + escaped + "[\"'][^>]+content=[\"']([^\"']+)[\"']"
            let b = "<meta[^>]+name=[\"']" + escaped + "[\"'][^>]+content=[\"']([^\"']+)[\"']"
            if let m = firstMatch(a, html) { return decodeEntities(m) }
            if let m = firstMatch(b, html) { return decodeEntities(m) }
        }
        return nil
    }
    private static func firstTitle(_ html: String) -> String? {
        if let m = firstMatch("<title[^>]*>(.*?)</title>", html) { return decodeEntities(m) }
        return nil
    }
    private static func firstLabeled(_ html: String, labels: [String]) -> String {
        for label in labels {
            let e = NSRegularExpression.escapedPattern(for: label)
            let p = e + "[ ]*[:-][ ]*([^<]{1,120})"
            if let v = firstMatch(p, html) { return decodeEntities(v) }
        }
        return ""
    }
    private static func imageSources(_ html: String, base: URL) -> [(URL, String)] {
        let p = "<img([^>]+?)src=[\"']([^\"']+)[\"']"
        guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { return [] }
        let r = NSRange(html.startIndex..<html.endIndex, in: html)
        return re.matches(in: html, range: r).compactMap { m in
            guard m.numberOfRanges > 2 else { return nil }
            guard let ra = Range(m.range(at: 1), in: html) else { return nil }
            guard let rb = Range(m.range(at: 2), in: html) else { return nil }
            guard let u = absoluteURL(String(html[rb]), base: base) else { return nil }
            return (u, String(html[ra]))
        }
    }
    private static func imageSourcesWithHints(_ html: String, base: URL) -> [(URL, String)] {
        return imageSources(html, base: base)
    }
    private static func classifyImage(url: URL, hint: String, isFirst: Bool) -> ImageRole {
        let t = (url.absoluteString + " " + hint).lowercased()
        if t.contains("cover") { return .cover }
        if t.contains("gallery") { return .gallery }
        if t.contains("sample") { return .gallery }
        if t.contains("thumb") { return .gallery }
        return isFirst ? .poster : .gallery
    }
    private static func absoluteURL(_ raw: String, base: URL) -> URL? {
        let c = raw.replacingOccurrences(of: "&amp;", with: "&")
        let s = c.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("//") { return URL(string: "https:" + s) }
        if let u = URL(string: s), u.scheme != nil { return u }
        return URL(string: s, relativeTo: base)?.absoluteURL
    }
    private static func firstMatch(_ p: String, _ t: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { return nil }
        let r = NSRange(t.startIndex..<t.endIndex, in: t)
        guard let m = re.firstMatch(in: t, range: r) else { return nil }
        guard m.numberOfRanges > 1 else { return nil }
        guard let rc = Range(m.range(at: 1), in: t) else { return nil }
        return String(t[rc])
    }
    private static func decodeEntities(_ v: String) -> String {
        var s = v.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&#39;", with: "'")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        return s
    }
}
