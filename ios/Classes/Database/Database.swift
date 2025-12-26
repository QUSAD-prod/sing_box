import Foundation

// Simplified Database version for Flutter plugin
// Uses UserDefaults for simple data
// For complex data, CoreData or SQLite can be used in the future

public enum Database {
    // For Flutter plugin use UserDefaults
    // In the future, SQLite/CoreData can be added for more complex data
    
    public static func save<T: Codable>(_ value: T, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            NSLog("Database save error: \(error)")
        }
    }
    
    public static func load<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            NSLog("Database load error: \(error)")
            return nil
        }
    }
    
    public static func delete(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

