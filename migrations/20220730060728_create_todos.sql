CREATE TABLE IF NOT EXISTS todos
(
    id          INTEGER PRIMARY KEY NOT NULL,
    title       TEXT                NOT NULL,
    completed   BOOLEAN             NOT NULL DEFAULT 0,
    item_order  INTEGER             NULL
);