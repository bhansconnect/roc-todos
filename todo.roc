app "todo"
    packages { pf: "platform/main.roc" }
    imports [pf.Effect.{Effect, always, after}]
    provides [main] to pf

dbFetchOne = \str, params, cont ->
    DBFetchOne str params cont |> always

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
        # {k: "Access-Control-Allow-Private-Network", v: "true"},
        {k: "Content-Type", v: "application/json"},
        {k: "Access-Control-Request-Method", v: "OPTIONS, GET, POST, PATCH, DELETE"},
        {k: "Server", v: "Roc-Hyper"},
    ]
    # There is always a starting "/" so we ignore the first element of pathList (always "")
    route = List.get pathList 1
    when T method route is
        T Get (Ok "") ->
            # TODO: return list of TODOs as json
            Response {status: 200, body: "[]", headers} |> always
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
                        {url: "\(baseUrl)/(idStr)", title, completed, itemOrder}
                    # todoResult <- fetchTodo 1
                    when todoResult is
                        Ok {url, title: Some title, completed: Some completed, itemOrder} ->
                            completedStr =
                                when completed is
                                    True -> "true"
                                    False -> "false"
                            itemOrderStr =
                                when itemOrder is
                                    Some x ->
                                        xStr = Num.toStr x
                                        ", order: \(xStr)"
                                    None ->
                                        ""
                            # TODO replace this with json encoding
                            Response {status: 200, body: "{url: \(url), title: \(title), completed: \(completedStr)\(itemOrderStr)}", headers} |> always
                        Ok {title: _, completed: _} ->
                            # Either title or completed is None, this should be impossible.
                            Response {status: 500, body: "Loaded invalid TODO?", headers} |> always
                        _ ->
                            Response {status: 400, body: "", headers} |> always
                _ ->
                    Response {status: 404, body: "", headers} |> always
        T Options _ ->
            # Options header is a CORS request.
            # Just accept this so that things can work while running from local network.
            Response {status: 204, body: "", headers} |> always
        _ ->
            Response {status: 404, body: "", headers} |> always

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
    
