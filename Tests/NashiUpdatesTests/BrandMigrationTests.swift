import XCTest
@testable import NashiUpdates

final class BrandMigrationTests:XCTestCase {
    func testRepositoriesAreUsedExactlyAsSaved() throws {
        for slug in ["orkunisitmak/tangerine","orkunisitmak/nashi","example/nashi"] {
            let repository=try GitHubRepository(slug)
            XCTAssertEqual(UpdateBrandMigration.canonical(repository),repository)
            XCTAssertEqual(UpdateBrandMigration.credentialAccount(repository),repository)
        }
    }
    func testArchiveURLsAreAcceptedOnlyForTheSelectedRepository() throws {
        let url=URL(string:"https://github.com/ahmethalitdurusoy/nashi-app/releases/download/v0.7.12-43/Nashi-0.7.12-43.zip")!
        let current=GitHubUpdateClient(repository:UpdateBrandMigration.current,token:nil)
        XCTAssertEqual(try current.archiveReference(for:url),.release(tag:"v0.7.12-43",filename:"Nashi-0.7.12-43.zip"))
        XCTAssertThrowsError(try current.archiveReference(for:URL(string:"https://github.com/orkunisitmak/tangerine/releases/download/v0.6.0-24/Nashi-0.6.0-24.zip")!))
        XCTAssertThrowsError(try current.archiveReference(for:URL(string:"https://github.com/orkunisitmak/nashi/releases/download/v1/a.zip")!))
    }
}
