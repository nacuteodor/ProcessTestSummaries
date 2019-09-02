//
//  JsonUtils.swift
//  ProcessTestSummaries
//
//  Created by Teodor Nacu on 23/05/16.
//  Copyright © 2016 Teo. All rights reserved.
//

import Foundation

extension JSON {

    static let kChildrenWildcard = "."
    static let kDescendantsWildcard = "*"
    static let kStarterWildcard = "^"

    /// Creates a JSON using a json string.
    /// E.g of json string: {"field1":"value1","field2":"value2","field3":{"field4:value4"}}
    /// - parameter string:  a json string
    public init(string: String) {
        if let dataFromString = string.data(using: String.Encoding.utf8, allowLossyConversion: true) {
            self.init(data: dataFromString)
        } else {
            self.init(NSNull())
        }
    }

    /// - returns: true if @absolutePath absolute path matches the @relativePath relative path
    /// The relative match may contain wildcards like "*" for matching descendants of a json node, or "." for matching the children of a json node
    fileprivate static func matchesRelativePath(_ relativePath: [JSONSubscriptType], absolutePath: [JSONSubscriptType]) -> Bool {
        let starterSequence: [JSONSubscriptType] = [kStarterWildcard]
        var relativePath = relativePath
        let fromStart = relativePath.starts(with: starterSequence) { (element, starter) -> Bool in
            return element == starter
        }
        if fromStart {
            relativePath.removeFirst()
        }
        if relativePath.count == 0 {
            return true
        }
        if absolutePath.count < relativePath.count {
            return false
        }
        var currentMatchedFieldIndex = 0
        var currentFieldFromRelativePath: JSONSubscriptType = ""
        var matches = false
        for var fieldIndex in 0..<absolutePath.count {
            let field = absolutePath[fieldIndex]
            if currentMatchedFieldIndex < relativePath.count {
                currentFieldFromRelativePath = relativePath[currentMatchedFieldIndex]
                if field != currentFieldFromRelativePath && currentFieldFromRelativePath != kChildrenWildcard {
                    if currentFieldFromRelativePath != kDescendantsWildcard {
                        if currentMatchedFieldIndex < 1 || relativePath[currentMatchedFieldIndex - 1] != kDescendantsWildcard {
                            fieldIndex -= currentMatchedFieldIndex
                            currentMatchedFieldIndex = 0
                        }
                    } else {
                        currentMatchedFieldIndex += 1
                    }
                } else {
                    currentMatchedFieldIndex += 1
                }
            } else {
                if  currentMatchedFieldIndex >= 2 && relativePath[currentMatchedFieldIndex - 2] != kDescendantsWildcard {
                    fieldIndex -= currentMatchedFieldIndex
                    currentMatchedFieldIndex = 0
                }
            }

            if fromStart && fieldIndex == 0  && currentMatchedFieldIndex == 0 && currentFieldFromRelativePath != kDescendantsWildcard {
                matches = false
                break
            }
            if  currentMatchedFieldIndex == relativePath.count {
                if fieldIndex == absolutePath.count - 1 && (field == currentFieldFromRelativePath || currentFieldFromRelativePath == kChildrenWildcard) {
                    matches = true
                    break
                } else if currentMatchedFieldIndex >= relativePath.count - 1 && currentFieldFromRelativePath == kDescendantsWildcard {
                    matches = true
                    break
                }
            }
        }
        return matches
    }

    /// - parameter json: The json where to find the @relativePath
    /// - parameter relativePath: The target json's relative path.
    /// Wildcard chars for children and descendants are supported in the json path: "." for children values of a json node, "*".
    /// Also, '^' can be used as the prefix the relative path to match the absolute path from beginning (beginning of the line).
    /// For e.g.: let jsonPath: [JSONSubscriptType] = ["field1", ".", "*", "field2"]
    /// - parameter currentPath: The absolute json path for getting to @json value
    /// - returns: Returns the absolute paths matching the relative path @relativePath
    static fileprivate func paths(_ json: JSON, _ relativePath: [JSONSubscriptType], _ currentPath: [JSONSubscriptType], lastPathsLimit: Int = Int.max, maxArrayCount: Int = Int.max) -> [[JSONSubscriptType]] {
        var absolutePaths: [[JSONSubscriptType]] = [[JSONSubscriptType]]()
        if json == JSON.null {
            return absolutePaths
        }
        if matchesRelativePath(relativePath, absolutePath: currentPath) {
            absolutePaths.append(currentPath)
            if absolutePaths.count > lastPathsLimit {
                absolutePaths.removeLast(absolutePaths.count - lastPathsLimit)
            }
            if absolutePaths.count == lastPathsLimit {
                return absolutePaths
            }
        }
        let starterSequence: [JSONSubscriptType] = [kStarterWildcard]
        let fromStart = relativePath.starts(with: starterSequence) { (element, starter) -> Bool in
            return element == starter
        }
        if fromStart {
            // check if the current path is a good path to go, else return
            let maxPathCount = [relativePath.count, currentPath.count].max()!
            let partialRelativePath = [JSONSubscriptType](relativePath.dropLast(maxPathCount - currentPath.count > 0 ? maxPathCount - currentPath.count - 1 : 0))
            let startsWithCurrentPath =  matchesRelativePath(partialRelativePath, absolutePath: currentPath)
            if !startsWithCurrentPath {
                return absolutePaths
            }
        }
        switch json.type {
        case .dictionary:
            for (key, value) in json.dictionaryValue {
                var newCurrentPath = currentPath
                newCurrentPath.append(key)
                let partialPaths = paths(value, relativePath, newCurrentPath, lastPathsLimit: lastPathsLimit, maxArrayCount: maxArrayCount)
                absolutePaths += partialPaths
                if absolutePaths.count > lastPathsLimit {
                    absolutePaths.removeLast(absolutePaths.count - lastPathsLimit)
                }
                if absolutePaths.count == lastPathsLimit {
                    return absolutePaths
                }
            }
        case .array:
            let firstIndex = json.arrayValue.count > maxArrayCount ? json.arrayValue.count - maxArrayCount : 0
            let lastIndex = json.arrayValue.count
            var range = stride(from: firstIndex, to: lastIndex, by: 1)
            if lastPathsLimit != Int.max {
                range = stride(from: lastIndex - 1, to: firstIndex - 1, by: -1)
            }
            for index in range {
                let value = json.arrayValue[index]
                var newCurrentPath = currentPath
                newCurrentPath.append(index)
                let partialPaths = paths(value, relativePath, newCurrentPath, lastPathsLimit: lastPathsLimit, maxArrayCount: maxArrayCount)
                absolutePaths += partialPaths
                if absolutePaths.count > lastPathsLimit {
                    absolutePaths.removeLast(absolutePaths.count - lastPathsLimit)
                }
                if absolutePaths.count == lastPathsLimit {
                    return absolutePaths
                }
            }
        default:
            break
        }
        return absolutePaths
    }

    /// - parameter relativePath: The target json's relative path
    /// - returns: Returns the absolute paths matching the relative path @relativePath in current json
    public func paths(relativePath: [JSONSubscriptType], lastPathsLimit: Int = Int.max, maxArrayCount: Int = Int.max) -> [[JSONSubscriptType]] {
        let paths: [[JSONSubscriptType]] = JSON.paths(self, relativePath, [JSONSubscriptType](), lastPathsLimit: lastPathsLimit, maxArrayCount: maxArrayCount)
        return paths
    }

    /// Get the json values found using the absolute paths @paths
    /// - parameter paths: an array with absolute json paths
    public func values(paths: [[JSONSubscriptType]]) -> [JSON] {
        var values = [JSON]()
        for path in paths {
            values.append(self[path])
        }
        return values
    }

    /// Get the json values found using the relative path @relativePath
    /// - parameter relativePath: The target json's relative path
    public func values(relativePath: [JSONSubscriptType], lastPathsLimit: Int = Int.max, maxArrayCount: Int = Int.max) -> [JSON] {
        let absolutePaths = paths(relativePath: relativePath, lastPathsLimit: lastPathsLimit, maxArrayCount: maxArrayCount)
        return values(paths: absolutePaths)
    }

    /// Get the json parents for the values found using the relative path @relativePath
    /// - parameter relativePath: The target json's relative path
    /// - parameter value: the json value from relative path @relativePath
    public func getParentValuesFor(relativePath: [JSONSubscriptType], lastPathsLimit: Int = Int.max, maxArrayCount: Int = Int.max, withValue value: JSON, contained: Bool = false) -> [JSON] {
        let absolutePaths = paths(relativePath: relativePath, lastPathsLimit: lastPathsLimit, maxArrayCount: maxArrayCount)
        let filteredAbsolutePaths = absolutePaths.filter({ (path) -> Bool in
            let pathValue = self[path]
            return (!contained && pathValue == value) || (contained && (String(describing: pathValue).contains(String(describing: value)) || String(describing: value).isEmpty))
        })
        let parentAbsolutePaths = filteredAbsolutePaths.map { (path) -> [JSONSubscriptType] in
            var path = path
            if path.count == 0 {
                return []
            }
            path.removeLast()
            return path
        }
        return values(paths: parentAbsolutePaths)
    }

    /// Get the json value found using the relative path @relativePath from @index
    /// - parameter index: the index of the json value from the values found with the relative path
    /// - parameter relativePath: the target json's relative path
    public func getValueFromIndex(_ index: Int, relativePath: [JSONSubscriptType]) -> JSON {
        var jsonValues = values(relativePath: relativePath)

        if jsonValues.count == index {
            XCTFail("A value from \(index) index was not found for relative json path \(relativePath) field in json:\n\(self)")
            return JSON.null
        }

        return jsonValues[index]
    }

    /// Get the first json value found using the relative path @relativePath
    /// - parameter relativePath: The target json's relative path
    public func getFirstValue(relativePath: [JSONSubscriptType]) -> JSON {
        return getValueFromIndex(0, relativePath: relativePath)
    }

    /// Sets the values of a field found using a relative path @relativePath
    /// - parameter relativePath: The target json's relative path
    /// - parameter newValues: The new values used to update the fields found
    /// - returns: Returns the current json instance
    public mutating func updateValues(relativePath: [JSONSubscriptType], newValues: [JSON]) -> JSON {
        let absolutePaths = paths(relativePath: relativePath)
        if absolutePaths.count != newValues.count {
            XCTFail("Found absolute paths count \(absolutePaths.count) doesn't match the new values count \(newValues.count) to set! Please, correct the relative path or update the new values.")
        }
        for index in 0 ..< absolutePaths.count {
            let path = absolutePaths[index]
            self[path] = newValues[index]
        }
        return self
    }

    /// Convert JSON values @values to an array of type @T? where T is a JSON accepted type: String, Int, Bool, Dictionary, Array
    public static func optionalValues<T>(_ values: [JSON]) -> [T?] {
        var toValues = [T?]()
        for value in values {
            if let error = value.error {
                XCTFail("Couldn't convert JSON value \(value) to type \(String(describing: T.self)) . Json error: \(error)")
            }
            if value != JSON.null {
                toValues.append(value.object as? T)
            } else {
                toValues.append(nil)
            }
        }
        return toValues
    }

    /// Convert JSON values @values to an array of type @T where T is a JSON accepted type: String, Int, Bool, Dictionary, Array
    public static func values<T>(_ values: [JSON]) -> [T] {
        var toValues = [T]()
        let optValues: [T?] = optionalValues(values)
        for optionalValue in optValues {
            if let value = optionalValue {
                toValues.append(value)
            } else {
                XCTFail("Couldn't convert JSON value \(optionalValue) to type \(String(describing: T.self)).")
            }
        }
        return toValues
    }
}

private func ==(left: JSONSubscriptType, right: JSONSubscriptType) -> Bool {
    if (left is Int && right is String) || (left is String && right is Int) {
        return false
    }
    return String(describing: left) == String(describing: right)
}

private func !=(left: JSONSubscriptType, right: JSONSubscriptType) -> Bool {
    return !(left == right)
}

public func ==(left: [JSONSubscriptType], right: [JSONSubscriptType]) -> Bool {
    return String(describing: left) == String(describing: right)
}

/// Update the @jsonPath json path with placeholder values @placeholderValues . For e.g:
///
/// let jsonPath: [JSONSubscriptType] = ["test1", "$test2", "test3"]
/// let updatedJsonPath = updateJsonPath(jsonPath, withPlaceholderValues: 1)
///
/// => updatedJsonPath will contain ["test1", 1, "test3"]
///
/// - parameter jsonPath the json path to update.
/// - parameter placeholderPrefix: the prefix string used to identify the placeholders from json path. The default prefix is "$".
/// - parameter withPlaceholderValues: the SubscriptType values in the right order for replacing the placeholders found in json path.
/// - returns: the updated json path.
public func updateJsonPath(_ jsonPath: [JSONSubscriptType], placeholderPrefix: String = "$", withPlaceholderValues placeholderValues: JSONSubscriptType...) -> [JSONSubscriptType] {
    var jsonPath = jsonPath
    let originalJsonPath = jsonPath
    var actualPlaceholdersCount = 0
    for i in 0 ..< jsonPath.count {
        let field = jsonPath[i]
        if let fieldString = field as? String {
            if fieldString.hasPrefix(placeholderPrefix) {
                actualPlaceholdersCount += 1
                if placeholderValues.count < actualPlaceholdersCount {
                    XCTFail("There is no placeholder value passed for placeholder \(fieldString)")
                }
                jsonPath.replaceSubrange(i...i, with: [placeholderValues[actualPlaceholdersCount - 1]])
            }
        }
    }
    if placeholderValues.count > actualPlaceholdersCount {
        XCTFail("There are too many placeholder values passed to the function: original json path \(originalJsonPath) with \(actualPlaceholdersCount) placeholders, the expected placeholder values: \(placeholderValues)")
    }
    return jsonPath
}
