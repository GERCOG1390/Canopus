import GRDB
import Foundation

enum SchemaCreator {
    static func createSchema(in db: Database) throws {
        // Metadata
        try db.execute(sql: """
            CREATE TABLE meta (
                key   TEXT PRIMARY KEY,
                value TEXT
            );
            """)

        // Hierarchy
        try db.execute(sql: """
            CREATE TABLE categories (
                id        INTEGER PRIMARY KEY,
                name      TEXT    NOT NULL,
                published INTEGER NOT NULL
            );

            CREATE TABLE groups (
                id          INTEGER PRIMARY KEY,
                category_id INTEGER NOT NULL REFERENCES categories(id),
                name        TEXT    NOT NULL,
                published   INTEGER NOT NULL
            );

            CREATE TABLE market_groups (
                id          INTEGER PRIMARY KEY,
                parent_id   INTEGER REFERENCES market_groups(id),
                name        TEXT    NOT NULL,
                description TEXT,
                icon_id     INTEGER,
                has_types   INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE types (
                id                  INTEGER PRIMARY KEY,
                group_id            INTEGER NOT NULL REFERENCES groups(id),
                market_group_id     INTEGER REFERENCES market_groups(id),
                name                TEXT    NOT NULL,
                description         TEXT,
                mass                REAL,
                volume              REAL,
                capacity            REAL,
                packaged_volume     REAL,
                portion_size        INTEGER,
                base_price          REAL,
                published           INTEGER NOT NULL,
                meta_group_id       INTEGER,
                variation_parent_id INTEGER,
                faction_id          INTEGER,
                race_id             INTEGER
            );

            CREATE INDEX idx_types_group        ON types(group_id);
            CREATE INDEX idx_types_market_group ON types(market_group_id);
            """)

        // FTS
        try db.execute(sql: """
            CREATE VIRTUAL TABLE types_fts USING fts5(
                name,
                content='types',
                content_rowid='id',
                tokenize='unicode61'
            );
            """)

        // Dogma
        try db.execute(sql: """
            CREATE TABLE dogma_attributes (
                id            INTEGER PRIMARY KEY,
                name          TEXT    NOT NULL,
                display_name  TEXT,
                unit_id       INTEGER,
                icon_id       INTEGER,
                high_is_good  INTEGER NOT NULL DEFAULT 0,
                stackable     INTEGER NOT NULL DEFAULT 1,
                default_value REAL,
                published     INTEGER NOT NULL DEFAULT 0,
                category_id   INTEGER,
                tooltip       TEXT
            );

            CREATE TABLE dogma_effects (
                id                              INTEGER PRIMARY KEY,
                name                            TEXT    NOT NULL,
                display_name                    TEXT,
                effect_category                 INTEGER NOT NULL DEFAULT 0,
                is_offensive                    INTEGER,
                is_assistance                   INTEGER,
                duration_attribute_id           INTEGER,
                discharge_attribute_id          INTEGER,
                range_attribute_id              INTEGER,
                falloff_attribute_id            INTEGER,
                tracking_speed_attribute_id     INTEGER,
                fitting_usage_chance_attribute_id INTEGER,
                modifier_info                   TEXT
            );

            CREATE TABLE type_attributes (
                type_id      INTEGER NOT NULL REFERENCES types(id),
                attribute_id INTEGER NOT NULL REFERENCES dogma_attributes(id),
                value        REAL    NOT NULL,
                PRIMARY KEY (type_id, attribute_id)
            ) WITHOUT ROWID;

            CREATE TABLE type_effects (
                type_id    INTEGER NOT NULL REFERENCES types(id),
                effect_id  INTEGER NOT NULL REFERENCES dogma_effects(id),
                is_default INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (type_id, effect_id)
            ) WITHOUT ROWID;
            """)

        // Derived tables
        try db.execute(sql: """
            CREATE TABLE skill_requirements (
                type_id  INTEGER NOT NULL,
                skill_id INTEGER NOT NULL,
                level    INTEGER NOT NULL,
                PRIMARY KEY (type_id, skill_id)
            ) WITHOUT ROWID;

            CREATE TABLE type_traits (
                type_id  INTEGER NOT NULL,
                skill_id INTEGER,
                bonus    REAL,
                unit_id  INTEGER,
                text     TEXT NOT NULL,
                sort     INTEGER NOT NULL
            );
            """)

        // Universe: regions, constellations, systems with their coordinates (metres), stargate links
        try db.execute(sql: """
            CREATE TABLE regions (
                id   INTEGER PRIMARY KEY,
                name TEXT NOT NULL
            );

            CREATE TABLE constellations (
                id        INTEGER PRIMARY KEY,
                region_id INTEGER NOT NULL,
                name      TEXT    NOT NULL
            );

            CREATE TABLE systems (
                id               INTEGER PRIMARY KEY,
                constellation_id INTEGER NOT NULL,
                name             TEXT    NOT NULL,
                security         REAL    NOT NULL,
                x REAL, y REAL, z REAL
            );

            -- Stargate links, one row per direction (from mapStargates).
            CREATE TABLE jumps (
                from_id INTEGER NOT NULL,
                to_id   INTEGER NOT NULL,
                PRIMARY KEY (from_id, to_id)
            ) WITHOUT ROWID;

            CREATE TABLE stations (
                id        INTEGER PRIMARY KEY,
                system_id INTEGER NOT NULL,
                name      TEXT    NOT NULL,
                type_id   INTEGER
            );
            """)

        // Dogma modifier chains (parsed from dogmaEffects.jsonl modifierInfo)
        try db.execute(sql: """
            CREATE TABLE dogma_modifiers (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                effect_id        INTEGER NOT NULL,
                domain           TEXT    NOT NULL DEFAULT '',
                func             TEXT    NOT NULL DEFAULT '',
                group_id         INTEGER,
                modified_attr_id INTEGER NOT NULL,
                modifying_attr_id INTEGER NOT NULL,
                operation        INTEGER NOT NULL,
                skill_type_id    INTEGER
            );
            CREATE INDEX idx_dogma_modifiers_effect ON dogma_modifiers(effect_id);
            """)

        // Localisation stub (EN only for v1, schema ready for more)
        try db.execute(sql: """
            CREATE TABLE names (
                type_id INTEGER NOT NULL,
                lang    TEXT    NOT NULL,
                value   TEXT    NOT NULL,
                PRIMARY KEY (type_id, lang)
            ) WITHOUT ROWID;
            """)

        // Russian texts (importer 3): kind = type / group / category / market_group / attribute / unit /
        // meta_group / race / faction / certificate; field = name / description / tooltip.
        try db.execute(sql: """
            CREATE TABLE l10n (
                kind  TEXT    NOT NULL,
                id    INTEGER NOT NULL,
                field TEXT    NOT NULL,
                lang  TEXT    NOT NULL,
                value TEXT    NOT NULL
            );
            CREATE UNIQUE INDEX idx_l10n ON l10n(kind, id, field, lang);

            -- Russian item descriptions, zlib-compressed (NSData .zlib): the biggest texts in the SDE.
            CREATE TABLE type_descriptions_ru (type_id INTEGER PRIMARY KEY, z BLOB NOT NULL);

            -- Ship traits in Russian, the same rows as type_traits.
            CREATE TABLE type_traits_ru (
                type_id  INTEGER NOT NULL,
                skill_id INTEGER,
                bonus    REAL,
                unit_id  INTEGER,
                text     TEXT NOT NULL,
                sort     INTEGER NOT NULL
            );
            CREATE INDEX idx_type_traits_ru ON type_traits_ru(type_id);

            CREATE TABLE dogma_units (
                id           INTEGER PRIMARY KEY,
                name         TEXT,
                display_name TEXT
            );
            CREATE TABLE attribute_categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
            CREATE TABLE meta_groups (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
            CREATE TABLE races (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
            CREATE TABLE factions (id INTEGER PRIMARY KEY, name TEXT NOT NULL);

            -- Blueprints: activities (manufacturing, invention, copying, research_*, reaction).
            CREATE TABLE blueprints (id INTEGER PRIMARY KEY, max_runs INTEGER);
            CREATE TABLE blueprint_activities (
                blueprint_id INTEGER NOT NULL, activity TEXT NOT NULL, time INTEGER NOT NULL,
                PRIMARY KEY (blueprint_id, activity)
            ) WITHOUT ROWID;
            CREATE TABLE blueprint_materials (blueprint_id INTEGER NOT NULL, activity TEXT NOT NULL, type_id INTEGER NOT NULL, quantity INTEGER NOT NULL);
            CREATE INDEX idx_bp_materials_bp ON blueprint_materials(blueprint_id);
            CREATE INDEX idx_bp_materials_type ON blueprint_materials(type_id);
            CREATE TABLE blueprint_products (blueprint_id INTEGER NOT NULL, activity TEXT NOT NULL, type_id INTEGER NOT NULL, quantity INTEGER NOT NULL, probability REAL);
            CREATE INDEX idx_bp_products_bp ON blueprint_products(blueprint_id);
            CREATE INDEX idx_bp_products_type ON blueprint_products(type_id);
            CREATE TABLE blueprint_skills (blueprint_id INTEGER NOT NULL, activity TEXT NOT NULL, skill_id INTEGER NOT NULL, level INTEGER NOT NULL);
            CREATE INDEX idx_bp_skills_bp ON blueprint_skills(blueprint_id);

            -- Reprocessing yield at 100% (per portion).
            CREATE TABLE type_materials (type_id INTEGER NOT NULL, material_id INTEGER NOT NULL, quantity INTEGER NOT NULL);
            CREATE INDEX idx_type_materials ON type_materials(type_id);

            -- Certificates (skill levels for basic … elite) and ship masteries (level 1–5 → certificates).
            CREATE TABLE certificates (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
            CREATE TABLE certificate_skills (
                certificate_id INTEGER NOT NULL, skill_id INTEGER NOT NULL,
                basic INTEGER NOT NULL, standard INTEGER NOT NULL, improved INTEGER NOT NULL,
                advanced INTEGER NOT NULL, elite INTEGER NOT NULL
            );
            CREATE INDEX idx_certificate_skills ON certificate_skills(certificate_id);
            CREATE TABLE masteries (type_id INTEGER NOT NULL, level INTEGER NOT NULL, certificate_id INTEGER NOT NULL);
            CREATE INDEX idx_masteries ON masteries(type_id);
            CREATE INDEX idx_skill_requirements_skill ON skill_requirements(skill_id);
            """)
    }
}
