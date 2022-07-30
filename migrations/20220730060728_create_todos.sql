CREATE TABLE IF NOT EXISTS todos
(
    id          INTEGER PRIMARY KEY NOT NULL,
    title       TEXT                NOT NULL,
    completed   BOOLEAN             NOT NULL DEFAULT FALSE,
    item_order  INTEGER             NULL
);