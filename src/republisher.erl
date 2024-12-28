-module(republisher).
-export([start/5, terminate/1]).

start(ValuesTable, RoutingTable, K, T, BucketSize) ->
    thread:start(
        fun()->
            republish_behaviour(ValuesTable, RoutingTable, K, T, BucketSize)
        end
    )
.

terminate(Pid) ->
    exit(Pid, kill).

republish_behaviour(ValuesTable, RoutingTable, K, T, BucketSize) ->
    thread:check_verbose(),
    receive
    after T ->
        ValuesMapList = ets:tab2list(ValuesTable),
        lists:foreach(
            fun({_, ValuesMap}) ->
                ValueList = maps:to_list(ValuesMap),
                lists:foreach(
                    fun({Key,Value}) ->
                        node:store_value(Key, Value, RoutingTable, K, BucketSize)
                    end,
                    ValueList
                )
            end,
            ValuesMapList
        ),
        republish_behaviour(ValuesTable, RoutingTable, K, T, BucketSize)
    end
.