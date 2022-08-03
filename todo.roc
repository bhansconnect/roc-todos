app "todo"
    packages { pf: "platform/main.roc" }
    imports [pf.Effect.{Effect, always, after}]
    provides [main] to pf

# Spec
# Get / -> Load all todos as a json
# Post / -> create todo from json
# Delete / -> delete all todos
# Get /<id> -> load todo with id
# Patch /<id> -> update todo with id from json
# Delete /<id> -> delete todo with id

main = \baseUrl, req ->
    method <- Effect.method req |> after
    path <- Effect.path req |> after
    pathList = Str.split path "/"
    headers = [
        {k: "Access-Control-Allow-Origin", v: "*"},
        {k: "Access-Control-Allow-Headers", v: "Content-Type"},
        {k: "Access-Control-Allow-Methods", v: "OPTIONS, GET, POST, PATCH, DELETE"},
        {k: "Access-Control-Allow-Private-Network", v: "true"},
        {k: "Content-Type", v: "application/json"},
        {k: "Server", v: "Roc-Hyper"},
    ]
    # There is always a starting "/" so we ignore the first element of pathList (always "")
    route = List.get pathList 1
    when T method route is
        T Post (Ok "") ->
            # TODO: Make this not terrible
            result <- loadBody
            when result is
                Ok body ->
                    when loadJsonKVs body is
                        Ok kvs ->
                            order =
                                when loadJsonI64Value kvs "order" is
                                    Ok i ->
                                        Int i
                                    Err _ ->
                                        Null
                            when loadJsonStringValue kvs "title" is
                                Ok title ->
                                    insertResult <- dbExecute "INSERT INTO todos (title, item_order) VALUES (?1, ?2)" [Text title, order]
                                    when insertResult is
                                        Ok {lastInsertRowId: id} ->
                                            rowResult <- dbFetchOne "SELECT id, title, completed, item_order FROM todos WHERE id = ?1" [Int id]
                                            rowResultHttp = mapErrToHttp rowResult headers 500
                                            resultHttp =
                                                row <- Result.try rowResultHttp
                                                todoResult = loadRowToTodo row baseUrl
                                                todoResultHttp = mapErrToHttp todoResult headers 500
                                                todo <- Result.map todoResultHttp
                                                # TODO replace this with json encoding
                                                todoStr = writeTodo "" todo
                                                {status: 200, body: todoStr, headers}
                                            mergeResult resultHttp |> Response |> always
                                        Err _ ->
                                            Response {status: 500, body: "", headers} |> always
                                Err _ ->
                                    Response {status: 400, body: "", headers} |> always
                        Err _ ->
                            Response {status: 400, body: "", headers} |> always
                Err _ ->
                    Response {status: 500, body: "", headers} |> always
        T Delete (Ok "") ->
            result <- dbExecute "DELETE FROM todos" []
            when result is
                Ok _ ->
                    Response {status: 200, body: "", headers} |> always
                Err _ ->
                    Response {status: 500, body: "", headers} |> always
        T Get (Ok "") ->
            rowsResult <- dbFetchAll "SELECT id, title, completed, item_order FROM todos" []
            # TODO: Change all of this to use json encoding.
            todosResult = Result.map rowsResult \rows ->
                todoRows =
                    row <- List.map rows
                    id =
                        when List.get row 0 is
                            Ok (Int i) ->
                                Some i
                            _ ->
                                None
                    title =
                        when List.get row 1 is
                            Ok (Text t) ->
                                Some t
                            _ ->
                                None
                    completed =
                        when List.get row 2 is
                            Ok (Boolean b) ->
                                Some b
                            _ ->
                                None
                    itemOrder =
                        when List.get row 3 is
                            Ok (Int i) ->
                                Some i
                            _ ->
                                None
                    {id, title, completed, itemOrder}
                optionalBody =
                    {first, optionalBuf}, todo <- List.walkUntil todoRows {first: True, optionalBuf: (Some "[")}
                    when T optionalBuf todo is
                        T (Some buf) {id: Some id, title: Some title, completed: Some completed, itemOrder} ->
                            idStr = Num.toStr id
                            url =  "\(baseUrl)/\(idStr)"
                            nextBuf =
                                if first then
                                    writeTodo buf {url, title, completed, itemOrder}
                                else
                                    Str.concat buf ", "
                                        |> writeTodo {url, title, completed, itemOrder}
                            Continue {first: False, optionalBuf: Some nextBuf}
                        _ ->
                            Break {first, optionalBuf: None}
                when optionalBody is
                    {optionalBuf: Some body} -> Some (Str.concat body "]")
                    {optionalBuf: None} -> None
            when todosResult is
                Ok (Some body) ->
                    Response {status: 200, body, headers} |> always
                _ ->
                    Response {status: 500, body: "", headers} |> always
        T Delete (Ok idStr) ->
            when Str.toI64 idStr is
                Ok id ->
                    result <- dbExecute "DELETE FROM todos WHERE id = ?1" [Int id]
                    when result is
                        Ok {rowsAffected: 1} ->
                            Response {status: 200, body: "", headers} |> always
                        Ok _ ->
                            Response {status: 400, body: "", headers} |> always
                        Err _ ->
                            Response {status: 500, body: "", headers} |> always
                _ ->
                    Response {status: 400, body: "", headers} |> always
        T Get (Ok idStr) ->
            when Str.toI64 idStr is
                Ok id ->
                    rowResult <- dbFetchOne "SELECT title, completed, item_order FROM todos WHERE id = ?1" [Int id]
                    todoResult = Result.map rowResult \row ->
                        title =
                            when List.get row 0 is
                                Ok (Text t) ->
                                    Some t
                                _ ->
                                    None
                        completed =
                            when List.get row 1 is
                                Ok (Boolean b) ->
                                    Some b
                                _ ->
                                    None
                        itemOrder =
                            when List.get row 2 is
                                Ok (Int i) ->
                                    Some i
                                _ ->
                                    None
                        {url: "\(baseUrl)/\(idStr)", title, completed, itemOrder}
                    # todoResult <- fetchTodo 1
                    when todoResult is
                        Ok {url, title: Some title, completed: Some completed, itemOrder} ->
                            # TODO replace this with json encoding
                            body = writeTodo "" {url, title, completed, itemOrder}
                            Response {status: 200, body, headers} |> always
                        Ok {title: _, completed: _} ->
                            # Either title or completed is None, this should be impossible.
                            Response {status: 500, body: "Loaded invalid TODO?", headers} |> always
                        Err NotFound ->
                            Response {status: 404, body: "", headers} |> always
                        Err QueryFailed ->
                            Response {status: 500, body: "", headers} |> always
                _ ->
                    Response {status: 404, body: "", headers} |> always
        T Options _ ->
            # Options header is a CORS request.
            # Just accept this so that things can work while running from local network.
            Response {status: 204, body: "", headers} |> always
        _ ->
            Response {status: 404, body: "", headers} |> always

writeTodo = \buf0, {url, title, completed, itemOrder} ->
    completedStr =
        when completed is
            True -> "true"
            False -> "false"
    buf1 = Str.concat buf0 "{\"url\": \""
    buf2 = Str.concat buf1 url
    buf3 = Str.concat buf2 "\", \"title\": \""
    buf4 = Str.concat buf3 title
    buf5 = Str.concat buf4 "\", \"completed\": "
    buf6 = Str.concat buf5 completedStr
    when itemOrder is
        Some x ->
            xStr = Num.toStr x
            buf7 = Str.concat buf6 ", \"order\": "
            buf8 = Str.concat buf7 xStr
            Str.concat buf8 "}"
        None ->
            Str.concat buf6 "}"

loadJsonKVs = \body ->
    {after: bodyAfter} <- Result.try (Str.splitFirst body "{")
    # This works around a bug with Str.splitLast
    afterWithSpace = Str.concat bodyAfter " "
    {before} <- Result.try (Str.splitLast afterWithSpace "}")
    kvsList =
        kvPair <- List.map (Str.split before ",")
        {before: key, after: value} <- Result.map (Str.splitLast kvPair ":")
        T (Str.trim key) (Str.trim value)
    resultDict, kvResult <-List.walkUntil kvsList (Ok Dict.empty)
    when T resultDict kvResult is
        T (Ok dict) (Ok (T k v)) ->
            Continue (Ok (Dict.insert dict k v))
        T _ (Err e) ->
            Break (Err e)
        T (Err e) _ ->
            Break (Err e)
        _ ->
            Break (Err HowDidIGetHere)

mapErrToHttp : Result a b, List {k: Str, v: Str}, U16 -> Result a {status: U16, body: Str, headers: List {k: Str, v: Str}}
mapErrToHttp = \result, headers, status ->
    when result is
        Ok v -> Ok v
        Err _ ->
            Err {status, body: "", headers}


mergeResult : Result a a -> a
mergeResult = \result ->
    when result is
        Ok v -> v
        Err v -> v

loadJsonI64Value = \kvs, key ->
    valStr <- Result.try (Dict.get kvs "\"\(key)\"") 
    Str.toI64 valStr

loadJsonStringValue = \kvs, key ->
    val <- Result.try (Dict.get kvs "\"\(key)\"") 
    {after: valAfter} <- Result.try (Str.splitFirst val "\"")
    # This works around a bug with Str.splitLast
    afterWithSpace = Str.concat valAfter " "
    {before} <- Result.map (Str.splitLast afterWithSpace "\"")
    before

# Since I can't put a query in a function (yay bugs!), just process the result in a function.
loadRowToTodo = \row, baseUrl ->
    optionId =
        when List.get row 0 is
            Ok (Int i) ->
                Some i
            _ ->
                None
    optionTitle =
        when List.get row 1 is
            Ok (Text t) ->
                Some t
            _ ->
                None
    optionCompleted =
        when List.get row 2 is
            Ok (Boolean b) ->
                Some b
            _ ->
                None
    itemOrder =
        when List.get row 3 is
            Ok (Int i) ->
                Some i
            _ ->
                None
    when T optionId optionTitle optionCompleted is
        T (Some id) (Some title) (Some completed) ->
            idStr = Num.toStr id
            url =  "\(baseUrl)/\(idStr)"
            Ok {url, title, completed, itemOrder}
        _ ->
            Err InvalidTodo

# Some reason I can't pull this out into another function.
# Type checking fails despite printing a matching type.
# fetchTodo = \id, todoCont ->
#     rowResult <- dbFetchOne "SELECT title, completed, item_order FROM todos WHERE id = ?1" [Int id]
#     todoResult = Result.map rowResult \row ->
#         title =
#             when List.get row 0 is
#                 Ok (Text t) ->
#                     Some t
#                 _ ->
#                     None
#         completed =
#             when List.get row 1 is
#                 Ok (Boolean b) ->
#                     Some b
#                 _ ->
#                     None
#         itemOrder =
#             when List.get row 2 is
#                 Ok (Int i) ->
#                     Some i
#                 _ ->
#                     None
#         {title, completed, itemOrder}
#     out =
#         when todoResult is
#             Ok {title: Some title, completed: Some completed, itemOrder: itemOrder} ->
#                 Ok {title, completed, itemOrder}
#             Ok _ ->
#                 Err InvalidTodo
#             Err _ ->
#                 Err QueryError
#     todoCont out

dbExecute = \str, params, cont ->
    DBExecute str params cont |> always

dbFetchAll = \str, params, cont ->
    DBFetchAll str params cont |> always

dbFetchOne = \str, params, cont ->
    DBFetchOne str params cont |> always

loadBody = \cont ->
    LoadBody cont |> always
