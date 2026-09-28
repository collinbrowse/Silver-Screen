//
//  TMDBPageDecoding.swift
//  TheSilverScreen
//
//  Decodes paged `results` one element at a time so one bad row does not
//  discard the rest of the page.
//

import Foundation

enum TMDBPageDecoding {
    static func decode<DTO: Decodable>(
        _ type: DTO.Type,
        from data: Data,
        logger: any AppLogging,
        context: String
    ) throws -> (items: [DTO], page: Int, totalPages: Int) {
        let object: [String: Any]
        let results: [Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parsedResults = parsed["results"] as? [Any] else {
                throw AppError.decoding
            }
            object = parsed
            results = parsedResults
        } catch let error as AppError {
            throw error
        } catch {
            logger.error("\(context) page decode failed", category: .networking)
            throw AppError.decoding
        }

        let page = object["page"] as? Int ?? 1
        let totalPages = object["total_pages"] as? Int ?? page
        let decoder = JSONDecoder()
        var items: [DTO] = []
        var skipped = 0

        for element in results {
            guard JSONSerialization.isValidJSONObject(element) else {
                skipped += 1
                continue
            }
            do {
                let elementData = try JSONSerialization.data(withJSONObject: element)
                items.append(try decoder.decode(DTO.self, from: elementData))
            } catch {
                skipped += 1
            }
        }

        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed \(context) result(s)", category: .networking)
        }
        if items.isEmpty, !results.isEmpty {
            throw AppError.decoding
        }
        return (items, page, totalPages)
    }

    /// Decodes a JSON array one element at a time. A bad element is skipped and logged.
    /// A missing value or a value that is not an array yields an empty list so one
    /// appended section cannot fail the screen.
    static func elements<DTO: Decodable>(
        _ type: DTO.Type,
        from value: Any?,
        logger: any AppLogging,
        context: String
    ) -> [DTO] {
        guard let value else { return [] }
        guard let results = value as? [Any] else {
            logger.error("\(context) was not a list", category: .networking)
            return []
        }
        let decoder = JSONDecoder()
        var items: [DTO] = []
        var skipped = 0
        for element in results {
            guard JSONSerialization.isValidJSONObject(element) else {
                skipped += 1
                continue
            }
            do {
                let elementData = try JSONSerialization.data(withJSONObject: element)
                items.append(try decoder.decode(DTO.self, from: elementData))
            } catch {
                skipped += 1
            }
        }
        if skipped > 0 {
            logger.error("Skipped \(skipped) malformed \(context) result(s)", category: .networking)
        }
        return items
    }
}
