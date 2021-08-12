//
//  Configuration.swift
//  NFCReader
//
//  Created by InSeongHwang on 2021/08/12.
//

import Foundation

enum Configuration {
    enum Error: Swift.Error {
        case missingKey, invalidValue
    }
    
    static func value<T>(for key: String) throws -> T where T: LosslessStringConvertible {
        guard let object = Bundle.main.object(forInfoDictionaryKey: key) else { throw Error.missingKey }
        switch object {
            case let value as T:
                return value
            case let string as String:
                guard let value = T(string) else { fallthrough }
                return value
            default:
                throw Error.invalidValue
        }
    }
    
    static func hasKey(for key: String) -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: key) != nil else { return false }
        return true
    }
}
