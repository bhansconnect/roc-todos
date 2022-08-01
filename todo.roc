app "todo"
    packages { pf: "platform/main.roc" }
    imports [pf.Effect.{Effect, always, after}]
    provides [main] to pf

dbFetchOne = \str, params, cont ->
    DBFetchOne str params cont |> always

main = \req ->
    method <- Effect.method req |> after
    path <- Effect.path req |> after
    pathList = Str.split path "/"
    # There is always a starting "/" so we ignore the first element of pathList (always "")
    route = List.get pathList 1
    when T method route is
        T Get (Ok "") ->
            result <- dbFetchOne "SELECT title, completed, item_order FROM todos WHERE id = ?1" [Int 1]
            when result is
                Ok row ->
                    when List.get row 0 is
                        Ok (Text text) ->
                            Response {status: 200, body: text} |> always
                        _ ->
                            Response {status: 200, body: "Todo loaded but had no data?"} |> always
                Err _ ->
                    Response {status: 200, body: "No todo found"} |> always
        _ ->
            Response {status: 404, body: ""} |> always
