import Foundation
import SwiftData

/// The current schema's models.
public typealias Expense = KakeiboSchemaV2.Expense
public typealias LineItem = KakeiboSchemaV2.LineItem

/// Migrations between schema versions, oldest first.
public enum KakeiboMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [KakeiboSchemaV1.self, KakeiboSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [v1ToV2]
    }

    /// Adds `Expense.receiptNumber` (optional, so existing rows get nil).
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: KakeiboSchemaV1.self, toVersion: KakeiboSchemaV2.self)
}

public enum KakeiboStore {
    /// Folder name for receipt photos inside Application Support.
    public static let photosDirectoryName = "Receipts"

    /// The schema version new stores are created with.
    public typealias CurrentSchema = KakeiboSchemaV2

    /// The app's model container, using the current schema and migration plan.
    /// - Parameters:
    ///   - inMemory: true for tests and previews; nothing is written to disk.
    ///   - url: a store file to use instead of the default location (migration tests).
    public static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = if let url {
            ModelConfiguration(schema: schema, url: url)
        } else {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(for: schema, migrationPlan: KakeiboMigrationPlan.self, configurations: configuration)
    }
}
