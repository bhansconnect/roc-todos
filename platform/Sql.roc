interface Sql
    exposes [Data, Error, ExecuteResult]
    imports []

Data : [
    Boolean Bool,
    Int I64,
    Real F64,
    Text Str,
    Blob (List U8),
    Null,
]

Error : [
    QueryFailed,
    NotFound,
]

ExecuteResult : {
    lastInsertRowId: I64,
    rowsAffected: U64,
}