platform "cli"
    requires {} { main : _ }
    exposes []
    packages {}
    imports [pf.Effect.{ Effect, Request }, pf.Sql]
    provides [mainForHost]

mainForHost : Request -> Effect
    [
        DBFetchOne Str (List Sql.Data) ((Result (List Sql.Data) Sql.Error -> Effect Continuation) as DBFetchOneCont),
        LoadBody ((Result Str {} -> Effect Continuation) as LoadBodyCont),
        Response { body: Str, status: U16 }
    ] as Continuation
mainForHost = \req -> main req
