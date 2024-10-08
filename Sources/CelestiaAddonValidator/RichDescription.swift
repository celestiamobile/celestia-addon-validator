import Foundation

private enum NoteType {
    case note
    case important
    case warning

    init(string: String?) {
        guard let string else {
            self = .note
            return
        }
        switch string.lowercased() {
        case "important":
            self = .important
        case "warning":
            self = .warning
        case "note":
            fallthrough
        default:
            self = .note
        }
    }

    var htmlClass: String {
        switch self {
        case .note:
            return "note"
        case .important:
            return "important"
        case .warning:
            return "warning"
        }
    }

    var htmlLabel: String {
        switch self {
        case .note:
            return "Note"
        case .important:
            return "Important"
        case .warning:
            return "Warning"
        }
    }
}

struct RichDescription {
    let base: String
    let notes: [String]?
    let noteType: String?
    let coverImage: Image
    let detailImages: [Image]?
    let youtubeIDs: [String]?
    let additionalLeadingHTML: String?
    let additionalTrailingHTML: String?

    var html: String {
        var text = "<p>\(base)</p>\n"
        if let notes, !notes.isEmpty {
            let noteContent: String
            let type = NoteType(string: noteType)
            if notes.count == 1 {
                noteContent = "<p>\(notes[0])</p>"
            } else {
                noteContent = "<ul>\(notes.map({ "<li>\($0)</li>" }).joined())</ul>"
            }
            text.append("<p></p><aside class=\"aside-container \(type.htmlClass)\"><p class=\"label\">\(type.htmlLabel)</p>\(noteContent)</aside><p></p>")
        }
        if let richCoverText = coverImage.caption {
            text.append("<p><img class=\"full-width-image\" src=\"{0}\"><i class=\"text-secondary-size text-secondary-color\">\(richCoverText)</i></p>\n")
        } else {
            text.append("<p><img class=\"full-width-image\" src=\"{0}\"></p>\n")
        }
        if let additionalLeadingHTML {
            text.append("<p></p>\(additionalLeadingHTML)<p></p>\n")
        }
        if let youtubeIDs, !youtubeIDs.isEmpty {
            text.append(youtubeIDs.map({ id in
                return "<p class=\"video-box\"><iframe src=\"https://www.youtube.com/embed/\(id)\" title=\"YouTube video player\" frameborder=\"0\" allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture\" allowfullscreen=\"\"></iframe></p>\n"
            }).joined())
        }
        if let detailImages, !detailImages.isEmpty {
            text.append(detailImages.enumerated().map({ (index, image) in
                if let caption = image.caption {
                    return "<p><img class=\"full-width-image\" src=\"{\(index + 1)}\"><i class=\"text-secondary-size text-secondary-color\">\(caption)</i></p>\n"
                }
                return "<p><img class=\"full-width-image\" src=\"{\(index + 1)}\"></p>\n"
            }).joined())
        }
        if let additionalTrailingHTML {
            text.append("<p></p>\(additionalTrailingHTML)<p></p>\n")
        }
        return text
    }
}
