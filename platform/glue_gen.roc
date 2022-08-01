platform "cli"
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [mainForHost]

SqlData : [
    Boolean Bool,
    Int I64,
    Real F64,
    Text Str,
    Blob (List U8),
    Null,
]

SqlError : [
    QueryFailed,
    # This is added to prevent a bindgen bug.
    OtherErr,
]


mainForHost : Result SqlData SqlError
mainForHost = main
