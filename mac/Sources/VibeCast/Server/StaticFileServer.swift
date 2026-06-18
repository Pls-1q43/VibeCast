// 从打包资源 Resources/web 提供前端静态文件。含路径穿越防护。

import Foundation

struct StaticFileServer {
    let webRoot: URL

    init?() {
        // SwiftPM `.copy("Resources/web")` → Bundle.module 下的 web 目录。
        guard let root = Bundle.module.url(forResource: "web", withExtension: nil) else {
            return nil
        }
        self.webRoot = root
    }

    init(webRoot: URL) {
        self.webRoot = webRoot
    }

    /// 解析请求路径到文件数据 + MIME。找不到返回 nil。
    func resolve(path: String) -> (data: Data, contentType: String)? {
        var rel = path
        if rel == "/" { rel = "/index.html" }
        // 去掉前导斜杠并规整。
        let cleaned = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel

        let candidate = webRoot.appendingPathComponent(cleaned).standardizedFileURL
        // 路径穿越防护：必须仍在 webRoot 之内。
        guard candidate.path.hasPrefix(webRoot.standardizedFileURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: candidate) else { return nil }
        return (data, HTTPResponse.mimeType(forPath: candidate.lastPathComponent))
    }
}
