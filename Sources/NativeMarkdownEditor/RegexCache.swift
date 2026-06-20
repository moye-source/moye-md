import Foundation

enum RegexCache {
    private static let lock = NSLock()
    private static var cache: [Key: NSRegularExpression] = [:]

    static func expression(
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        let key = Key(pattern: pattern, optionsRawValue: options.rawValue)

        lock.lock()
        if let expression = cache[key] {
            lock.unlock()
            return expression
        }
        lock.unlock()

        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        lock.lock()
        cache[key] = expression
        lock.unlock()
        return expression
    }

    private struct Key: Hashable {
        let pattern: String
        let optionsRawValue: UInt
    }
}
