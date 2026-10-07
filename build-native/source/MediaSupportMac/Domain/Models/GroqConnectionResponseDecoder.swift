import Foundation

enum GroqConnectionResponseDecoder {
    static func modelCount(from data: Data) throws -> Int {
        let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return response.data.count
    }
}

private struct ModelListResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}
