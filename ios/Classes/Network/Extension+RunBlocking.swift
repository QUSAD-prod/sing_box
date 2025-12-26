import Foundation

func runBlocking<T>(_ block: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = resultBox<T>()
    var taskCompleted = false
    Task.detached {
        let value = await block()
        box.result0 = value
        taskCompleted = true
        semaphore.signal()
    }
    semaphore.wait()
    // Check that task completed and value is set
    guard taskCompleted, let result0 = box.result0 else {
        NSLog("runBlocking: Task did not complete or result0 not set")
        fatalError("runBlocking: result0 not set - this should never happen")
    }
    return result0
}

func runBlocking<T>(_ tBlock: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = resultBox<T>()
    Task.detached {
        do {
            let value = try await tBlock()
            box.result = .success(value)
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.getResult()
}

private class resultBox<T> {
    var result: Result<T, Error>? = nil
    var result0: T? = nil
    
    func getResult() throws -> T {
        guard let result = result else {
            throw NSError(domain: "resultBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Result not set"])
        }
        return try result.get()
    }
    
    func getResult0() -> T {
        guard let result0 = result0 else {
            // This should not happen, as semaphore.wait() guarantees value is set
            // But just in case, return default value or throw error
            throw NSError(domain: "resultBox", code: -2, userInfo: [NSLocalizedDescriptionKey: "result0 not set in resultBox"])
        }
        return result0
    }
}

