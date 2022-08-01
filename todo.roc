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
        T Get (Ok idStr) ->
            id =
                when Str.toI64 idStr is
                    Ok i -> i
                    _ -> 0
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
                {id, title, completed, itemOrder}
            # todoResult <- fetchTodo 1
            when todoResult is
                Ok {title: Some title, completed: Some completed} ->
                    body =
                        when completed is
                            True -> "\(title)\t->\tCompleted"
                            False -> "\(title)\t->\tIn Progress"
                    Response {status: 200, body} |> always
                Ok {title: _, completed: _} ->
                    # Either title or completed is None, this should be impossible.
                    Response {status: 500, body: "Loaded invalid TODO..."} |> always
                _ ->
                    Response {status: 200, body: "No todo found with id \(idStr)"} |> always
        _ ->
            Response {status: 404, body: ""} |> always

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
    
