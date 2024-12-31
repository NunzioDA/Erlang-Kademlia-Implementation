% -----------------------------------------------------------------------------
% Module: republisher
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-20
% Description: This module manages the republisher thread that republish 
%              ValueTable content every T milliseconds
% -----------------------------------------------------------------------------

-module(republisher).
-export([start/5, republish_behaviour/5]).

% The republisher thread is started executing the
% republish_behaviour
start(ValuesTable, RoutingTable, K, T, BucketSize) ->
    thread:start(
        fun()->
            ?MODULE:republish_behaviour(ValuesTable, RoutingTable, K, T, BucketSize)
        end
    )
.

% Every T seconds the republisher takes the ValuesMap and foreach 
% value it starts a store procedure
republish_behaviour(ValuesTable, RoutingTable, K, T, BucketSize) ->
    timer:sleep(T),
    % Update verbosity
    thread:check_verbose(),
    % Republish every element in the value table
    ValuesMapList = ets:tab2list(ValuesTable),
    lists:foreach(
        fun({_, ValuesMap}) ->
            ValueList = maps:to_list(ValuesMap),
            lists:foreach(
                fun({Key,Value}) ->
                    node:distribute_value(Key, Value, RoutingTable, K, BucketSize)
                end,
                ValueList
            )
        end,
        ValuesMapList
    ),
    % Repeat
    ?MODULE:republish_behaviour(ValuesTable, RoutingTable, K, T, BucketSize)
.