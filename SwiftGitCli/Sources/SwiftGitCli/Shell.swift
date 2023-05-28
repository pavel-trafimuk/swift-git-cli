//
//  File.swift
//  
//
//  Created by Pavel Trafimuk on 28/05/2023.
//

import Foundation
import ColorizeSwift

// Error type thrown by the `shell` function, in case the given command failed
public struct ShellError: Error {
    /// The termination status of the command that was run
    public let terminationStatus: Int32
    /// The error message as a UTF8 string, as returned through `STDERR`
    public var message: String { return errorData.shellOutput() }
    /// The raw error buffer data, as returned through `STDERR`
    public let errorData: Data
    /// The raw output buffer data, as retuned through `STDOUT`
    public let outputData: Data
    /// The output of the command as a UTF8 string, as returned through `STDOUT`
    public var output: String { return outputData.shellOutput() }
}

extension ShellError: CustomStringConvertible {
    public var description: String {
        return """
               Shell encountered an error
               Status code: \(terminationStatus)
               Message: "\(message)"
               Output: "\(output)"
               """
    }
}

extension ShellError: LocalizedError {
    public var errorDescription: String? {
        return description
    }
}

public enum Shell {
    
    public static var globalPath: String?
    
    @discardableResult
    public static func run(_ command: String,
                           verbose: Int,
                           at path: String? = nil,
                           outputHandle: FileHandle? = nil,
                           handleErrorOutput: Bool = false,
                           errorHandle: FileHandle? = nil) throws -> String {
        
        guard let launchPath = path ?? Shell.globalPath else {
            throw ShellError(terminationStatus: 1,
                             errorData: "No Global Path Found".data(using: .utf8)!,
                             outputData: "No Global Path Found".data(using: .utf8)!)
        }
        let finalCommand = "cd \(launchPath.escapingSpaces) && \(command)"
        if verbose > 0 {
            print("$ \(command)".darkGray())
        }
        var outputData = Data()
        var errorData = Data()
        
        // Because FileHandle's readabilityHandler might be called from a
        // different queue from the calling queue, avoid a data race by
        // protecting reads and writes to outputData and errorData on
        // a single dispatch queue.
        let outputQueue = DispatchQueue(label: "bash-output-queue")
        
        let task = Process()
        let SHELL = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        task.launchPath = SHELL
        task.arguments = ["-c", finalCommand]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handler in
            let data = handler.availableData
            outputQueue.async {
                outputData.append(data)
                outputHandle?.write(data)
            }
        }
        
        var errorPipe: Pipe?
        if handleErrorOutput {
            errorPipe = Pipe()
            task.standardError = errorPipe
            errorPipe?.fileHandleForReading.readabilityHandler = { handler in
                let data = handler.availableData
                outputQueue.async {
                    errorData.append(data)
                    errorHandle?.write(data)
                }
            }
        }
        
        task.launch()
        task.waitUntilExit()
        
        if let handle = outputHandle, !handle.isStandard {
            handle.closeFile()
        }
        
        if let handle = errorHandle, !handle.isStandard {
            handle.closeFile()
        }
        
        outputPipe.fileHandleForReading.readabilityHandler = nil
        if handleErrorOutput {
            errorPipe?.fileHandleForReading.readabilityHandler = nil
        }
        
        // Block until all writes have occurred to outputData and errorData,
        // and then read the data back out.
        return try outputQueue.sync {
            let result = outputData.shellOutput()
            if task.terminationStatus != 0 {
                print("Failed: \(result)".red())
                throw ShellError(
                    terminationStatus: task.terminationStatus,
                    errorData: errorData,
                    outputData: outputData
                )
            }
            if verbose > 0, !result.isEmpty {
                print(result)
            }
            return result
        }
    }
}

extension String {
    var escapingSpaces: String {
        return replacingOccurrences(of: " ", with: "\\ ")
    }
}

extension Data {
    func shellOutput() -> String {
        guard let output = String(data: self, encoding: .utf8) else {
            return ""
        }
        
        guard !output.hasSuffix("\n") else {
            let endIndex = output.index(before: output.endIndex)
            return String(output[..<endIndex])
        }
        
        return output
        
    }
}

extension FileHandle {
    var isStandard: Bool {
        return self === FileHandle.standardOutput ||
        self === FileHandle.standardError ||
        self === FileHandle.standardInput
    }
}
