-module(store_mnesia).
-copyright('Synrc Research Center s.r.o.').
-include("config.hrl").
-include("user.hrl").
-include("entry.hrl").
-include("comment.hrl").
-include("subscription.hrl").
-include("feed.hrl").
-include("acl.hrl").
-include("metainfo.hrl").
-include_lib("stdlib/include/qlc.hrl").
-compile(export_all).

start()    -> mnesia:start().
stop()     -> mnesia:stop().
delete()   -> mnesia:delete_schema([node()]).
version()  -> {version,"KVS MNESIA"}.
dir()      -> [{table,atom_to_list(T)}||T<-mnesia:system_info(local_tables)].
join()     -> mnesia:change_table_copy_type(schema, node(), disc_copies), initialize().
join(Node) ->
    mnesia:change_config(extra_db_nodes, [Node]),
    mnesia:change_table_copy_type(schema, node(), disc_copies),
    [{Tb, mnesia:add_table_copy(Tb, node(), Type)}
     || {Tb, [{Node, Type}]} <- [{T, mnesia:table_info(T, where_to_commit)}
                               || T <- mnesia:system_info(tables)]].

initialize() ->
    kvs:info("Mnesia Init"),
    mnesia:create_schema([node()]),
    [ kvs:init(store_mnesia,Module) || Module <- kvs:modules() ],
    mnesia:wait_for_tables([ T#table.name || T <- kvs:tables()],5000).

index(RecordName,Key,Value) ->
    Table = kvs:table(RecordName),
    Index = string:str(Table#table.fields,[Key]),
    flatten(fun() -> mnesia:index_read(RecordName,Value,Index+1) end).

get(RecordName, Key) -> just_one(fun() -> mnesia:read(RecordName, Key) end).
put(Records) when is_list(Records) -> void(fun() -> lists:foreach(fun mnesia:write/1, Records) end);
put(Record) -> put([Record]).
delete(Tab, Key) -> mnesia:transaction(fun()-> mnesia:delete({Tab, Key}) end), ok.
count(RecordName) -> mnesia:table_info(RecordName, size).
all(RecordName) -> flatten(fun() -> Lists = mnesia:all_keys(RecordName), [ mnesia:read({RecordName, G}) || G <- Lists ] end).
next_id(RecordName, Incr) -> mnesia:dirty_update_counter({id_seq, RecordName}, Incr).
flatten(Fun) -> case mnesia:transaction(Fun) of {atomic, R} -> lists:flatten(R); _ -> [] end.
many(Fun) -> case mnesia:transaction(Fun) of {atomic, R} -> R; _ -> [] end.
void(Fun) -> case mnesia:transaction(Fun) of {atomic, ok} -> ok; {aborted, Error} -> {error, Error} end.
create_table(Name,Options) -> mnesia:create_table(Name, Options).
add_table_index(Record, Field) -> mnesia:add_table_index(Record, Field).
exec(Q) -> F = fun() -> qlc:e(Q) end, {atomic, Val} = mnesia:transaction(F), Val.
just_one(Fun) ->
    case mnesia:transaction(Fun) of
        {atomic, []} -> {error, not_found};
        {atomic, [R]} -> {ok, R};
        {atomic, [_|_]} -> {error, duplicated};
        _ -> {error, not_found} end.