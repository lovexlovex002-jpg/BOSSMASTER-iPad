import Foundation

struct NativeFetchEngine {
    private let session: URLSession
    init() {
        let config=URLSessionConfiguration.default; config.waitsForConnectivity=true; config.timeoutIntervalForRequest=20; config.timeoutIntervalForResource=35
        config.httpAdditionalHeaders=["User-Agent":"Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1"]
        session=URLSession(configuration:config)
    }
    func search(code:String) async throws -> [SearchRecord] {
        let c=code.lowercased()
        let sources:[(String,String)]=[
            ("JAVCT","https://javct.net/v/\(c)"),("JAVGG","https://javgg.net/\(c)/"),("SupJAV","https://supjav.com/\(c)/"),("JAVGURU","https://jav.guru/\(c)/"),("MissAV","https://missav.ws/en/\(c)"),("NJAV","https://njav.tv/en/v/\(c)"),("JAVTRAILERS","https://javtrailers.com/video/\(c)")
        ]
        return await withTaskGroup(of:SearchRecord?.self,returning:[SearchRecord].self){group in
            for (name,raw) in sources { if let url=URL(string:raw) { group.addTask { await self.fetchRecord(code:code,source:name,url:url) } } }
            var out:[SearchRecord]=[]; for await item in group { if let item {out.append(item)} }; return out
        }
    }
    func search(urlString:String) async throws -> [SearchRecord] {
        guard let url=URL(string:urlString),let scheme=url.scheme?.lowercased(),["http","https"].contains(scheme) else {throw FetchError.invalidURL}
        let code=url.lastPathComponent.isEmpty ? (url.host ?? "URL") : url.lastPathComponent.uppercased()
        if let r=await fetchRecord(code:code,source:url.host ?? "URL",url:url){return [r]}; return []
    }
    private func fetchRecord(code:String,source:String,url:URL) async -> SearchRecord? {
        do { var req=URLRequest(url:url); req.httpMethod="GET"; req.timeoutInterval=20; let (data,response)=try await session.data(for:req); guard let http=response as? HTTPURLResponse,(200...399).contains(http.statusCode) else{return nil}; return HTMLRecordParser.parse(code:code,source:source,url:url,data:data) } catch {return nil}
    }
}
enum FetchError:LocalizedError { case invalidURL; var errorDescription:String?{"text":"ลิงก์ไม่ถูกต้อง กรุณาวาง URL ที่ขึ้นต้นด้วย http:// หรือ https://"}}
enum HTMLRecordParser {
    static func parse(code:String,source:String,url:URL,data:Data)->SearchRecord {
        let html=String(data:data,encoding:.utf8) ?? String(decoding:data,as:UTF8.self)
        var r=SearchRecord(code:code.uppercased(),source:source,pageURL:url)
        r.title=firstMeta(html,keys:["og:title","twitter:title"]) ?? firstTitle(html) ?? ""
        r.plot=firstMeta(html,keys:["og:description","description"]) ?? ""
        var candidates:[(URL,String)]=[]
        if let s=firstMeta(html,keys:["og:image","twitter:image"]),let u=absoluteURL(s,base:url){candidates.append((u,"og-image"))}
        candidates += imageSourcesWithHints(html,base:url).prefix(20)
        var seen=Set<URL>()
        for (u,hint) in candidates where seen.insert(u).inserted {
            r.images.append(ImageItem(url:u,role:classifyImage(url:u,hint:hint,isFirst:r.images.isEmpty)))
            if r.images.count>=11{break}
        }
        r.actor=firstLabeled(html,labels:["Actor","Actress","Cast"]); r.studio=firstLabeled(html,labels:["Studio","Maker"]); r.releaseDate=firstLabeled(html,labels:["Release Date","Released"]); r.runtime=firstLabeled(html,labels:["Runtime","Duration"])
        return r
    }
    private static func firstMeta(_ html:String,keys:[String])->String? {
        for key in keys { let e=NSRegularExpression.escapedPattern(for:key); for p in [#"<meta[^>]+property=["']#(e)["'][^>]+content=["']([^"']+)["']"#,#"<meta[^>]+name=["']#(e)["'][^>]+content=["']([^"']+)["']"#] { if let m=firstMatch(p,html){return decodeEntities(m)} } }; return nil
    }
    private static func firstTitle(_ html:String)->String? { firstMatch(#"<title[^>]*>(.*?)</title>"#,html).map(decodeEntities) }
    private static func firstLabeled(_ html:String,labels:[String])->String { for label in labels { let e=NSRegularExpression.escapedPattern(for:label); if let v=firstMatch(#"#(e)s*[:-]s*(?:</?w+[^>]*>s*)?([^<]{1,120})"#,html){return decodeEntities(v)} }; return "" }
    private static func imageSourcesWithHints(_ html:String,base:URL)->[(URL,String)] {
        let p=#"<img([^>]+?)(?:src|data-src)=["']([^"']+)["']"#; guard let re=try?NSRegularExpression(pattern:p,options:[.caseInsensitive,.dotMatchesLineSeparators])else{return[]}
        let range=NSRange(html.startIndex..<html.endIndex,in:html); return re.matches(in:html,range:range).compactMap{m in guard m.numberOfRanges>2,let a=Range(m.range(at:1),in:html),let b=Range(m.range(at:2),in:html),let u=absoluteURL(String(html[b]),base:base)else{return nil};return(u,String(html[a]))}
    }
    private static func classifyImage(url:URL,hint:String,isFirst:Bool)->ImageRole { let s=(url.absoluteString+" "+hint).lowercased(); if s.contains("cover"){return .cover}; if s.contains("gallery")||s.contains("sample")||s.contains("thumb"){return .gallery}; return isFirst ? .poster : .gallery }
    private static func absoluteURL(_ raw:String,base:URL)->URL? { let c=raw.replacingOccurrences(of:"&amp;",with:"&").trimmingCharacters(in:.whitespacesAndNewlines); if c.hasPrefix("//"){return URL(string:"https:"+c)}; if let u=URL(string:c),u.scheme != nil{return u}; return URL(string:c,relativeTo:base)?.absoluteURL }
    private static func firstMatch(_ pattern:String,_ text:String)->String? { guard let re=try?NSRegularExpression(pattern:pattern,options:[.caseInsensitive,.dotMatchesLineSeparators])else{return nil}; let range=NSRange(text.startIndex..<text.endIndex,in:text); guard let m=re.firstMatch(in:text,range:range),m.numberOfRanges>1,let r=Range(m.range(at:1),in:text)else{return nil};return String(text[r]) }
    private static func decodeEntities(_ v:String)->String { v.replacingOccurrences(of:"&amp;",with:"&").replacingOccurrences(of:"&quot;",with:""").replacingOccurrences(of:"&#39;",with:"'").replacingOccurrences(of:"&lt;",with:"<").replacingOccurrences(of:"&gt;",with:">") }
}
