import Foundation

struct MOOMessage {
    var verb: String
    var name: String
    var service: String?
    var requestID: String
    var body: [String: Any]?
}

final class MOOClient {
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onRequest: ((MOOMessage) -> Void)?

    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var requestID = 0
    private var callbacks: [String: (MOOMessage) -> Void] = [:]

    init(host: String, port: Int) {
        url = URL(string: "ws://\(host):\(port)/api")!
    }

    func connect() {
        AppLogger.info("MOO", "websocket connect url=\(url.absoluteString)")
        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        onOpen?()
        receiveNext()
    }

    func close() {
        AppLogger.info("MOO", "websocket close url=\(url.absoluteString)")
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        callbacks.removeAll()
        onClose?()
    }

    func sendRequest(_ name: String, body: [String: Any]? = nil, callback: ((MOOMessage) -> Void)? = nil) {
        let currentID = String(requestID)
        requestID += 1

        if let callback {
            callbacks[currentID] = callback
        }

        sendFrame(verb: "REQUEST", name: name, requestID: currentID, body: body)
        AppLogger.debug("MOO", "sent request name=\(name) requestID=\(currentID)")
    }

    func sendComplete(requestID: String, name: String, body: [String: Any]? = nil) {
        sendFrame(verb: "COMPLETE", name: name, requestID: requestID, body: body)
    }

    func sendContinue(requestID: String, name: String, body: [String: Any]? = nil) {
        sendFrame(verb: "CONTINUE", name: name, requestID: requestID, body: body)
    }

    private func sendFrame(verb: String, name: String, requestID: String, body: [String: Any]?) {
        var bodyData: Data?
        if let body {
            bodyData = try? JSONSerialization.data(withJSONObject: body, options: [])
        }

        var header = "MOO/1 \(verb) \(name)\nRequest-Id: \(requestID)\n"
        if let bodyData {
            header += "Content-Length: \(bodyData.count)\nContent-Type: application/json\n"
        }
        header += "\n"

        var data = Data(header.utf8)
        if let bodyData {
            data.append(bodyData)
        }

        task?.send(.data(data)) { error in
            if let error {
                AppLogger.error("MOO", "send failed verb=\(verb) name=\(name) error=\(error.localizedDescription)")
            }
        }
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handle(data)
                case .string(let string):
                    self.handle(Data(string.utf8))
                @unknown default:
                    break
                }
                self.receiveNext()
            case .failure:
                AppLogger.warning("MOO", "websocket receive failed; closing")
                self.close()
            }
        }
    }

    private func handle(_ data: Data) {
        guard let message = parse(data) else {
            AppLogger.error("MOO", "failed to parse moo message bytes=\(data.count)")
            close()
            return
        }

        if message.verb == "REQUEST" {
            AppLogger.debug("MOO", "received request service=\(message.service ?? "unknown") name=\(message.name)")
            onRequest?(message)
            return
        }

        if let callback = callbacks[message.requestID] {
            AppLogger.debug("MOO", "received response verb=\(message.verb) name=\(message.name) requestID=\(message.requestID)")
            callback(message)
            if message.verb == "COMPLETE" {
                callbacks.removeValue(forKey: message.requestID)
            }
        }
    }

    private func parse(_ data: Data) -> MOOMessage? {
        let separator = Data([0x0a, 0x0a])
        guard let headerRange = data.range(of: separator),
              let header = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }

        let lines = header.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first else { return nil }
        let firstParts = first.split(separator: " ", maxSplits: 2).map(String.init)
        guard firstParts.count == 3, firstParts[0] == "MOO/1" else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            headers[parts[0]] = parts[1].trimmingCharacters(in: .whitespaces)
        }

        guard let requestID = headers["Request-Id"] else { return nil }

        var body: [String: Any]?
        let bodyStart = headerRange.upperBound
        if bodyStart < data.endIndex,
           let json = try? JSONSerialization.jsonObject(with: data[bodyStart..<data.endIndex], options: []),
           let dictionary = json as? [String: Any] {
            body = dictionary
        }

        let verb = firstParts[1]
        if verb == "REQUEST" {
            let requestName = firstParts[2]
            let components = requestName.split(separator: "/", maxSplits: 1).map(String.init)
            guard components.count == 2 else { return nil }
            return MOOMessage(verb: verb, name: components[1], service: components[0], requestID: requestID, body: body)
        }

        return MOOMessage(verb: verb, name: firstParts[2], service: nil, requestID: requestID, body: body)
    }
}
