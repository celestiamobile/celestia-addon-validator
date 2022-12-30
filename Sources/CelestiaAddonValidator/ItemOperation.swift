import Foundation

public enum ItemOperation {
    case remove(item: RemoveItem)
    case update(item: UpdateItem)
    case create(item: CreateItem)
}
