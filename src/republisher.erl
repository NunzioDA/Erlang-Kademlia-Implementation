% -----------------------------------------------------------------------------
% Module: republisher
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-20
% Description: This module manages the republisher thread that republish 
%              ValueTable content every T milliseconds
% -----------------------------------------------------------------------------

-module(republisher).
-export([start/4, add_pair/2, republish_behaviour/6, check_for_new_pairs/4]).

% The republisher thread is started executing the
% republish_behaviour
start(RoutingTable, K, T, BucketSize) ->
    Pid = thread:start(
        fun()->
            CurrentMillis = erlang:monotonic_time(millisecond),            
            ?MODULE:republish_behaviour(#{},RoutingTable, K, T, BucketSize, CurrentMillis)
        end
    ),
    put(republisher_pid, Pid),
    Pid
.

% Send new pair to the republisher
% that will take care of publishing 
% and republishing it.
% The pair is sent to the republisher
% using the message new_pair
add_pair(Key, Value) ->
    case get(republisher_pid) of
        undefined -> utils:print("Start a republisher before adding pairs");
        Pid -> Pid ! {new_pair, Key, Value}
    end.

% Check for new pairs to add to the value table
% and distribute them to the network.
% New pairs are received from the add_pair function
% using the receive statement with new_pair message
check_for_new_pairs(ValuesTable, RoutingTable, K, BucketSize) ->
    receive
        {new_pair, Key, Value} ->
            NewMap = maps:put(Key,Value,ValuesTable),
            node:distribute_value(Key, Value, RoutingTable, K, BucketSize),
            NewMap
    after 10 -> % This has to be 10 ms to avoid blocking the network
        ValuesTable
    end.

% Every T seconds the republisher takes the ValuesMap and foreach 
% value it starts a store procedure
republish_behaviour(ValuesTable, RoutingTable, K, T, BucketSize, LastMillis) ->
    % Update verbosity
    thread:check_verbose(),
    CheckValueTable = ?MODULE:check_for_new_pairs(ValuesTable, RoutingTable, K, BucketSize),

    CurrentMillis = erlang:monotonic_time(millisecond),
    DeltaMillis = CurrentMillis - LastMillis,

    if DeltaMillis >= T ->

        % Republish every element in the value table
        ValueList = maps:to_list(CheckValueTable),
        NewValueTable = lists:foldl(
            fun({Key,Value}, PreviousValueTable) ->
                % Checking for new pairs while republishing the old ones
                NewValueTable = ?MODULE:check_for_new_pairs(PreviousValueTable, RoutingTable, K, BucketSize),
                % Republishing old pairs
                node:distribute_value(Key, Value, RoutingTable, K, BucketSize),
                NewValueTable
            end,
            CheckValueTable,
            ValueList
        ),        
        NewMillis = erlang:monotonic_time(millisecond);
    true ->
        NewValueTable = CheckValueTable,
        NewMillis = LastMillis
    end,

    % Repeat
    ?MODULE:republish_behaviour(NewValueTable, RoutingTable, K, T, BucketSize, NewMillis)
.