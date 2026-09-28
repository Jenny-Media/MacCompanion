import Foundation

/// No redirects, DTDs/entities, duplicate leaf fields or nested unbounded data.
final class NativeLaunchXML: NSObject, XMLParserDelegate {
    var fields: [String: String] = [:]
    var apps: [[String: String]] = []
    private var app: [String: String]?
    private var stack: [String] = []
    private var text = ""
    private var valid = true
    private var rootSeen = false
    static func parse(_ data: Data) throws -> NativeLaunchXML {
        guard data.count <= 1_048_576, let string = String(data: data, encoding: .utf8),
              !string.contains("<!") else { throw NativeLaunchFailure.invalidResponse }
        // Sunshine's legacy declaration says UTF-16 although its bytes are UTF-8.
        let normalized = string.replacingOccurrences(of: "UTF-16", with: "UTF-8", options: .caseInsensitive)
        let owner = NativeLaunchXML(), parser = XMLParser(data: Data(normalized.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = owner
        guard parser.parse(), owner.valid, owner.rootSeen, owner.stack.isEmpty else { throw NativeLaunchFailure.invalidResponse }
        return owner
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if stack.isEmpty {
            guard !rootSeen, name == "root", attributes["status_code"] == "200" else { valid = false; parser.abortParsing(); return }
            rootSeen = true
        } else if stack.count == 1, name == "App" {
            guard app == nil else { valid = false; parser.abortParsing(); return }
            app = [:]
        } else if stack.count > 2 || (stack.count == 2 && stack.last != "App") {
            valid = false; parser.abortParsing(); return
        }
        stack.append(name); text = ""
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
        if text.utf8.count > 4096 { valid = false; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard stack.last == name else { valid = false; parser.abortParsing(); return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if stack.count == 3 {
            if app?[name] != nil { valid = false; parser.abortParsing(); return }
            app?[name] = value
        } else if stack.count == 2, name == "App" {
            if let app { apps.append(app) }; app = nil
            if apps.count > 32 { valid = false; parser.abortParsing(); return }
        } else if stack.count == 2 {
            if fields[name] != nil { valid = false; parser.abortParsing(); return }
            fields[name] = value
        }
        stack.removeLast(); text = ""
    }
}
enum NativeLaunchFailure: Error { case unavailable, invalidResponse, invalidRoute, invalidMaterial }


enum NativeLaunchValidationV0 {
    static func validVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return value.count < 128 && parts.count == 4 && parts.enumerated().allSatisfy { index, part in
            guard let number = Int32(part) else { return false }; return index == 3 || number >= 0
        }
    }
    static func validStreamURL(_ value: String, address: String, port: Int) -> Bool {
        guard let url = URLComponents(string: value), url.scheme == "rtspenc", url.port == port,
              url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) == address,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return false }
        return true
    }
}
