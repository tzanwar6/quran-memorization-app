import Foundation

struct Surah: Codable, Identifiable, Equatable {
    let id: Int
    let arabicName: String
    let englishName: String
    let transliteration: String
    let verseCount: Int
    let pageStart: Int
    let pageEnd: Int
    let revelation: String
    
    var pageRange: String {
        if pageStart == pageEnd {
            return "Page \(pageStart)"
        } else {
            return "Pages \(pageStart)-\(pageEnd)"
        }
    }
    
    var isMeccan: Bool {
        revelation.lowercased() == "meccan"
    }
}
