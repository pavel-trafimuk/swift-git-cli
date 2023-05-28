import Foundation

public enum GitError: Error {
    case gitEnvironmentNotFound
}

public final class Git {
    
    public let localUrl: URL
    public let verbose: Int
    
    init(localUrl: URL, verbose: Int) {
        self.localUrl = localUrl
        self.verbose = verbose
    }
}

extension Git {
    
    @discardableResult
    private func shell(_ runBlock: String) throws -> String {
        try Shell.run(runBlock, verbose: verbose, at: localUrl.path)
    }
    
    public static func isRootOfGit(at url: URL, verbose: Int) -> Bool {
        guard let resultPath = try? Shell.run("git rev-parse --show-toplevel",
                                          verbose: verbose,
                                          at: url.path)
        else {
            return false
        }
        let resultUrl = URL(fileURLWithPath: resultPath)
        return resultUrl == url
    }
    
    public static func isPartOfGit(at url: URL, verbose: Int) -> Bool {
        guard let result = try? Shell.run("git rev-parse --is-inside-work-tree",
                                          verbose: verbose,
                                          at: url.path)
        else {
            return false
        }
        return result == "true"
    }
    
    @discardableResult
    public static func cloneIfNotExists(from url: URL, to localUrl: URL, verbose: Int) throws -> Git {
        guard !isRootOfGit(at: localUrl, verbose: verbose) else {
            return Git(localUrl: localUrl, verbose: verbose)
        }
        try Shell.run("git clone '\(url.absoluteString)' .", verbose: verbose, at: localUrl.path, handleErrorOutput: true)
        return Git(localUrl: localUrl, verbose: verbose)
    }
    
    @discardableResult
    public func fetchAll() throws -> Git {
        try shell("git fetch --prune --all --verbose")
        return self
    }

    @discardableResult
    public func checkout(branch: String) throws -> Git {
        try shell("git checkout --track -b \(branch) origin/\(branch)")
        return self
    }

    @discardableResult
    public func checkout(hash: String) throws -> Git {
        try shell("git checkout \(hash)")
        return self
    }
    
    @discardableResult
    public func syncSubmodules() throws -> Git {
        try shell("git submodule sync")
        return self
    }
    
    @discardableResult
    public func updateSubmodules() throws -> Git {
        try shell("git submodule update --init --recursive --force")
        return self
    }
    
    public func currentBranchName() throws -> String {
        let value = try shell("git branch --show-current")
        let stripped = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else {
            throw GitError.gitEnvironmentNotFound
        }
        return stripped
    }

    public func isStagedEmpty() throws -> Bool {
        let result = try shell("git diff --staged --numstat")
        return result.isEmpty
    }
    
    public func lastCommiter() throws -> String {
           try shell("git log -1 --pretty=format:'%an'")
       }
       // TODO:   implement mail
       // LAST_COMMITER_MAIL = Helper.backticks("echo $(git log -1 --pretty=format:'%ae') | #{GREP_CONDITION}")

    public func currentHash() throws -> String {
        try shell("git rev-parse HEAD")
    }

}
