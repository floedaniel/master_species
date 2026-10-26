-- One row per assessor / assessment status (dropdown lists)
CREATE TABLE IF NOT EXISTS assessors (
  name TEXT PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS statuses (
  name TEXT PRIMARY KEY
);

-- One row per species
CREATE TABLE IF NOT EXISTS species (
  species_id   INTEGER PRIMARY KEY AUTOINCREMENT,
  eppocode     TEXT NOT NULL UNIQUE,
  fullname     TEXT,
  authdesc     TEXT,
  kingdom      TEXT,
  phylum       TEXT,
  class        TEXT,
  "order"      TEXT,
  family       TEXT,
  genus        TEXT,
  eppo_list    TEXT CHECK (eppo_list IN ('A1 list', 'A2 list', 'Alert list')),
  eppo_status  TEXT CHECK (eppo_status IN ('active', 'removed_from_list')),
  date_flagged TEXT,
  added_at     TEXT DEFAULT (datetime('now')),
  updated_at   TEXT
);

-- One row per assessment of a species
CREATE TABLE IF NOT EXISTS assessments (
  assessment_id INTEGER PRIMARY KEY AUTOINCREMENT,
  species_id    INTEGER NOT NULL REFERENCES species (species_id) ON DELETE CASCADE,
  assessor      TEXT REFERENCES assessors (name) ON UPDATE CASCADE,
  status        TEXT REFERENCES statuses (name) ON UPDATE CASCADE,
  hours         REAL CHECK (hours >= 0),
  batch         INTEGER,
  ai            INTEGER CHECK (ai IN (0, 1)),
  endnote       TEXT,
  comment       TEXT,
  added_at      TEXT DEFAULT (datetime('now')),
  updated_at    TEXT
);

-- One row per EPPO list event (added / deleted / transient) of a species
CREATE TABLE IF NOT EXISTS eppo_list_events (
  species_id INTEGER NOT NULL REFERENCES species (species_id) ON DELETE CASCADE,
  event      TEXT NOT NULL CHECK (event IN ('added', 'deleted', 'transient')),
  year       INTEGER NOT NULL,
  PRIMARY KEY (species_id, event)
);

-- One row per changed field
CREATE TABLE IF NOT EXISTS change_log (
  change_id  INTEGER PRIMARY KEY AUTOINCREMENT,
  species_id INTEGER NOT NULL REFERENCES species (species_id) ON DELETE CASCADE,
  field      TEXT NOT NULL,
  old_value  TEXT,
  new_value  TEXT,
  changed_at TEXT DEFAULT (datetime('now')),
  changed_by TEXT
);
