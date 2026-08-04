import Foundation

final class UpdateService {
    static let latestReleaseEndpoint = URL(
        string: "https://api.github.com/repos/samni728/diskmount/releases/latest"
    )!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func check(currentVersion: String, completion: @escaping (AppUpdateState?) -> Void) {
        var request = URLRequest(url: Self.latestReleaseEndpoint)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DiskMount/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        session.dataTask(with: request) { data, response, _ in
            guard let data,
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let state = try? Self.updateState(from: data, currentVersion: currentVersion) else {
                completion(nil)
                return
            }
            completion(state)
        }.resume()
    }

    static func updateState(from data: Data, currentVersion: String) throws -> AppUpdateState {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let latestVersion = normalizedVersion(release.tagName)
        guard !release.draft,
              !release.prerelease,
              isTrustedReleaseURL(release.htmlURL),
              isVersion(latestVersion, newerThan: currentVersion) else {
            return .noUpdate
        }
        return AppUpdateState(
            available: true,
            latestVersion: latestVersion,
            releaseURL: release.htmlURL.absoluteString
        )
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = versionComponents(candidate)
        let currentParts = versionComponents(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidateValue = index < candidateParts.count ? candidateParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            if candidateValue != currentValue {
                return candidateValue > currentValue
            }
        }
        return false
    }

    static func isTrustedReleaseURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/samni728/diskmount/releases/")
    }

    private static func normalizedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }

    private static func versionComponents(_ value: String) -> [Int] {
        normalizedVersion(value)
            .split(separator: "-", maxSplits: 1)
            .first?
            .split(separator: ".")
            .map { Int($0) ?? 0 } ?? []
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}
