//
//  XCResultFile.swift
//  
//
//  Created by David House on 7/6/19.
//

import Foundation

public class XCResultFile {
    
    let url: URL
    
    public init(url: URL) {
        self.url = url
    }
    
    public func getInvocationRecord() -> ActionsInvocationRecord? {
        
        guard let getOutput = shell(command: ["-l", "-c", "xcrun xcresulttool get --path \"\(url.path)\" --format json"]) else {
            return nil
        }
        
        do {
            guard let data = getOutput.data(using: .utf8) else {
                print("Unable to turn string into data, must not be a utf8 string")
                return nil
            }
            
            guard let rootJSON = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: AnyObject] else {
                print("Expecting top level dictionary but didn't find one")
                return nil
            }
            
            let invocation = ActionsInvocationRecord(rootJSON)
            return invocation
        } catch {
            print("Error deserializing JSON: \(error)")
            return nil
        }
    }
    
    public func getTestPlanRunSummaries(id: String) -> ActionTestPlanRunSummaries? {
        
        guard let getOutput = shell(command: ["-l", "-c", "xcrun xcresulttool get --path \"\(url.path)\" --id \(id) --format json"]) else {
            return nil
        }
        
        do {
            guard let data = getOutput.data(using: .utf8) else {
                print("Unable to turn string into data, must not be a utf8 string")
                return nil
            }
            
            guard let rootJSON = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: AnyObject] else {
                print("Expecting top level dictionary but didn't find one")
                return nil
            }
            
            let runSummaries = ActionTestPlanRunSummaries(rootJSON)
            return runSummaries
        } catch {
            print("Error deserializing JSON: \(error)")
            return nil
        }
    }
    
    public func getActionTestSummaryAsJsonString(id: String) -> String? {
        return shell(command: ["-l", "-c", "xcrun xcresulttool get --path \"\(url.path)\" --id \(id) --format json"])
    }

    public func getActionTestSummary(id: String) -> ActionTestSummary? {
        guard let getOutput = getActionTestSummaryAsJsonString(id: id) else {
            return nil
        }

        do {
            guard let data = getOutput.data(using: .utf8) else {
                print("Unable to turn string into data, must not be a utf8 string")
                return nil
            }

            guard let rootJSON = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: AnyObject] else {
                print("Expecting top level dictionary but didn't find one")
                return nil
            }

            let summary = ActionTestSummary(rootJSON)
            return summary
        } catch {
            print("Error deserializing JSON: \(error)")
            return nil
        }
    }
    
    public func getPayload(id: String) -> Data? {        
        guard let getOutput = shellData(command: ["-l", "-c", "xcrun xcresulttool get --path \"\(url.path)\" --id \"\(id)\""]) else {
            return nil
        }

        return getOutput
    }
    
    public func exportPayload(id: String) -> URL? {
        
        let tempPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(id)
        _ = shell(command: ["-l", "-c", "xcrun xcresulttool export --type file --path \"\(url.path)\" --id \(id) --output-path \"\(tempPath.path)\""])
        return tempPath
    }
    
    public func getCodeCoverage() -> CodeCoverage? {
        
        guard let getOutput = shell(command: ["-l", "-c", "xcrun xccov view --report --json \"\(url.path)\""]) else {
            return nil
        }
        
        do {
            guard let data = getOutput.data(using: .utf8) else {
                print("Unable to turn string into data, must not be a utf8 string")
                return nil
            }
            
            let decoded = try JSONDecoder().decode(CodeCoverage.self, from: data)
            return decoded
        } catch {
            print("Error deserializing JSON: \(error)")
            return nil
        }
    }
    
    private func shellData(command: [String]) -> Data? {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = command
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return data
    }

    private func shell(command: [String]) -> String? {
        let data = shellData(command: command)
        guard let dataValue = data else {
            return nil
        }
        let output: String? = String(data: dataValue, encoding: String.Encoding.utf8)
        return output
    }
}
