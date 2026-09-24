import Testing
import GRDB
@testable import EVEStaticData
import Domain

@Suite("SDERepository")
struct SDERepositoryTests {

    private func makeRepo() throws -> SDERepository {
        let db = try DatabaseQueue()
        try db.write { db in
            try createSchema(db)
            try seedData(db)
        }
        return SDERepository(dbReader: db)
    }

    @Test func categoriesReturnPublished() async throws {
        let repo = try makeRepo()
        let cats = try await repo.categories()
        #expect(cats.count == 1)
        #expect(cats[0].name == "Modules")
    }

    @Test func groupsByCategoryId() async throws {
        let repo = try makeRepo()
        let groups = try await repo.groups(categoryId: 1)
        #expect(groups.count == 1)
        #expect(groups[0].name == "Shield")
    }

    @Test func typesByGroupId() async throws {
        let repo = try makeRepo()
        let types = try await repo.types(groupId: 10)
        #expect(types.count == 1)
        #expect(types[0].name == "Shield Extender I")
    }

    @Test func typeById() async throws {
        let repo = try makeRepo()
        let t = try await repo.type(id: 100)
        #expect(t?.name == "Shield Extender I")
    }

    @Test func attributesForType() async throws {
        let repo = try makeRepo()
        let attrs = try await repo.attributes(typeId: 100)
        #expect(attrs.count == 1)
        #expect(attrs[0].value == 500.0)
        #expect(attrs[0].attribute?.displayName == "Shield Capacity")
    }

    @Test func searchByPrefix() async throws {
        let repo = try makeRepo()
        let results = try await repo.search("Shield")
        #expect(!results.isEmpty)
        #expect(results[0].name == "Shield Extender I")
    }

    @Test func searchEmptyQueryReturnsEmpty() async throws {
        let repo = try makeRepo()
        let results = try await repo.search("   ")
        #expect(results.isEmpty)
    }

    // MARK: - Helpers

    private func createSchema(_ db: Database) throws {
        let statements: [String] = [
            "CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL, published INTEGER NOT NULL)",
            "CREATE TABLE groups (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL, name TEXT NOT NULL, published INTEGER NOT NULL)",
            """
            CREATE TABLE types (
                id INTEGER PRIMARY KEY, group_id INTEGER NOT NULL,
                market_group_id INTEGER, name TEXT NOT NULL, description TEXT,
                mass REAL, volume REAL, capacity REAL, packaged_volume REAL,
                portion_size INTEGER, base_price REAL, published INTEGER NOT NULL,
                meta_group_id INTEGER, variation_parent_id INTEGER,
                faction_id INTEGER, race_id INTEGER
            )
            """,
            "CREATE VIRTUAL TABLE types_fts USING fts5(name, content='types', content_rowid='id', tokenize='unicode61')",
            """
            CREATE TABLE dogma_attributes (
                id INTEGER PRIMARY KEY, name TEXT NOT NULL, display_name TEXT,
                unit_id INTEGER, icon_id INTEGER, high_is_good INTEGER NOT NULL,
                stackable INTEGER NOT NULL, default_value REAL, published INTEGER NOT NULL
            )
            """,
            "CREATE TABLE type_attributes (type_id INTEGER NOT NULL, attribute_id INTEGER NOT NULL, value REAL NOT NULL, PRIMARY KEY (type_id, attribute_id)) WITHOUT ROWID",
        ]
        for sql in statements {
            try db.execute(sql: sql)
        }
    }

    private func seedData(_ db: Database) throws {
        try db.execute(sql: "INSERT INTO categories VALUES (1, 'Modules', 1)")
        try db.execute(sql: "INSERT INTO groups VALUES (10, 1, 'Shield', 1)")
        try db.execute(sql: """
            INSERT INTO types VALUES
            (100, 10, NULL, 'Shield Extender I', 'Adds shield HP',
             0, 0.5, 0, NULL, 1, 100.0, 1, NULL, NULL, NULL, NULL)
            """)
        try db.execute(sql: "INSERT INTO types_fts(rowid, name) SELECT id, name FROM types")
        try db.execute(sql: "INSERT INTO dogma_attributes VALUES (263, 'shieldCapacity', 'Shield Capacity', 1, NULL, 1, 0, 0.0, 1)")
        try db.execute(sql: "INSERT INTO type_attributes VALUES (100, 263, 500.0)")
    }
}
