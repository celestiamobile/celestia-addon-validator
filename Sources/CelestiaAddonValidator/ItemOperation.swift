import Foundation

public enum ItemOperation {
    case remove(item: RemoveItem)
    case update(item: UpdateItem)
    case create(item: CreateItem)
}

public extension ItemOperation {
    var summary: String {
        switch self {
        case .remove(let item):
            return "Removing item with ID: \(item.id.recordName)"
        case .update(let item):
            var texts = ["Updating item with ID: \(item.id.recordName)"]
            if let title = item.title {
                texts.append("Title: \(title)")
            }
            if let description = item.description {
                texts.append("Descrpition: \(description)")
            }
            if let category = item.category {
                texts.append("Category: \(category.recordID.recordName)")
            }
            if let authors = item.authors {
                texts.append("Authors: \(authors.joined(separator: ", "))")
            }
            if let releaseDate = item.releaseDate {
                texts.append("Release Date: \(releaseDate)")
            }
            if let lastUpdateDate = item.lastUpdateDate {
                texts.append("Last Update Date: \(lastUpdateDate)")
            }
            if let demoObjectName = item.demoObjectName {
                texts.append("Demo Object Name: \(demoObjectName)")
            }
            if let relatedObjectPaths = item.relatedObjectPaths {
                texts.append("Related Object Paths: \(relatedObjectPaths)")
            }
            if item.coverImage != nil {
                texts.append("Has new cover image")
            }
            if item.addon != nil {
                texts.append("Has new add-on contents")
            }
            if item.richDescription != nil {
                texts.append("Has new rich description")
            }
            return texts.joined(separator: "\n")
        case .create(let item):
            var texts = ["Creating item"]
            if let idRequirement = item.idRequirement {
                texts.append("ID Requirement: \(idRequirement)")
            }
            texts.append("Title: \(item.title)")
            texts.append("Descrpition: \(item.description)")
            texts.append("Category: \(item.category.recordID.recordName)")
            texts.append("Authors: \(item.authors.joined(separator: ", "))")
            texts.append("Release Date: \(item.releaseDate)")
            if let lastUpdateDate = item.lastUpdateDate {
                texts.append("Last Update Date: \(lastUpdateDate)")
            }
            if let demoObjectName = item.demoObjectName {
                texts.append("Demo Object Name: \(demoObjectName)")
            }
            if let relatedObjectPaths = item.relatedObjectPaths {
                texts.append("Related Object Paths: \(relatedObjectPaths)")
            }
            if item.richDescription != nil {
                texts.append("Has new rich description")
            }
            return texts.joined(separator: "\n")
        }
    }
}
