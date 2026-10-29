import Foundation

/// UForge ships under its own bundle identifier, so no earlier install shares
/// its preferences or Keychain items. Repositories are used exactly as saved:
/// no rename mapping and no fallback to a previous brand's repository.
enum UpdateBrandMigration {
    static let current=try! GitHubRepository("ahmethalitdurusoy/nashi-app")
    static func canonical(_ repository:GitHubRepository)->GitHubRepository { repository }
    static func credentialAccount(_ repository:GitHubRepository)->GitHubRepository { repository }
    static func acceptsArchive(owner:String,name:String,for repository:GitHubRepository)->Bool {
        owner.lowercased()+"/"+name.lowercased()==repository.slug
    }
    /// Every feed and archive still requires the pinned Sparkle signature.
    static func latestFeed(repository:GitHubRepository,token:String?,configuration:URLSessionConfiguration = .ephemeral) async throws -> (GitHubUpdateClient,Data) {
        let client=GitHubUpdateClient(repository:repository,token:token,configuration:configuration)
        return (client,try await client.fetchLatestAppcast())
    }
}
