import Foundation

enum SOODPacket {
    static let serviceID = "00720724-5143-4a9b-abac-0e50cba674bb"
    static let multicastAddress = "239.255.90.90"
    static let port: UInt16 = 9003

    static func queryData(transactionID: String = UUID().uuidString) -> Data {
        var data = Data()
        data.append("SOOD".data(using: .utf8)!)
        data.append(2)
        data.append("Q".data(using: .utf8)!)
        append(name: "query_service_id", value: serviceID, to: &data)
        append(name: "_tid", value: transactionID, to: &data)
        return data
    }

    static func parse(_ data: Data, address: String, port: UInt16) -> RoonCore? {
        guard data.count >= 6,
              String(data: data.prefix(4), encoding: .utf8) == "SOOD",
              data[4] == 2 else {
            return nil
        }

        var position = 6
        var props: [String: String] = [:]

        while position < data.count {
            let nameLength = Int(data[position])
            position += 1
            guard nameLength > 0, position + nameLength <= data.count else { return nil }
            let nameData = data[position..<(position + nameLength)]
            position += nameLength

            guard position + 2 <= data.count else { return nil }
            let valueLength = (Int(data[position]) << 8) | Int(data[position + 1])
            position += 2
            guard valueLength != 65_535, position + valueLength <= data.count else { return nil }

            let valueData = data[position..<(position + valueLength)]
            position += valueLength

            if let name = String(data: nameData, encoding: .utf8),
               let value = String(data: valueData, encoding: .utf8) {
                props[name] = value
            }
        }

        guard props["service_id"] == serviceID,
              let uniqueID = props["unique_id"],
              let httpPortValue = props["http_port"],
              let httpPort = Int(httpPortValue) else {
            return nil
        }

        let replyHost = props["_replyaddr"] ?? address
        let displayName = props["display_name"] ?? props["name"] ?? "Roon Core"

        return RoonCore(
            id: uniqueID,
            name: displayName,
            host: replyHost,
            port: httpPort,
            source: .discovered,
            lastSeen: Date(),
            lastConnected: nil
        )
    }

    private static func append(name: String, value: String, to data: inout Data) {
        let nameData = name.data(using: .utf8)!
        let valueData = value.data(using: .utf8)!
        data.append(UInt8(nameData.count))
        data.append(nameData)
        data.append(UInt8((valueData.count >> 8) & 0xff))
        data.append(UInt8(valueData.count & 0xff))
        data.append(valueData)
    }
}
