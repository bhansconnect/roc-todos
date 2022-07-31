platform "cli"
    requires {} { main : _ }
    exposes []
    packages {}
    imports [pf.Effect.{ Effect, Future, Request }]
    provides [mainForHost]

SqlData : [
    Boolean Bool,
    Int I64,
    Real F64,
    Text Str,
    Blob (List U8),
]

SqlError : [
    QueryFailed,
    # This is added to prevent a bindgen bug.
    OtherErr,
]

mainForHost : Request -> Effect
    [
        DBFetchOne Str (List SqlData) ((Result (List SqlData) SqlError -> Effect Continuation) as DBRequestCont),
        LoadBody ((Result Str {} -> Effect Continuation) as LoadBodyCont),
        Response { body: Str, status: U16 }
    ] as Continuation
mainForHost = \req -> main req
