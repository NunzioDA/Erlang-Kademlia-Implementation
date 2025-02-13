% -----------------------------------------------------------------------------
% Module: republisher
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-20
% Description: This module manages the republisher thread that republish 
%              ValueTable content every T milliseconds
% -----------------------------------------------------------------------------

-module(republisher).
-export([start/5, add_pair/2, republish_behaviour/6, check_for_new_pairs/4]).

% The republisher thread is started executing the
% republish_behaviour.
start(RoutingTable, K, T, BucketSize, MyValuesTable) ->
    Pid = thread:start(
        fun()->
            CurrentMillis = erlang:monotonic_time(millisecond),            
            ?MODULE:republish_behaviour(MyValuesTable,RoutingTable, K, T, BucketSize, CurrentMillis)
        end
    ),
    thread:save_named(republisher_pid, Pid),
    Pid
.

% Send new pair to the republisher
% that will take care of publishing 
% and republishing it.
% The pair is sent to the republisher
% using the message new_pair
add_pair(Key, Value) ->
    case thread:get_named(republisher_pid) of
        undefined -> utils:print("Start a republisher before adding pairs");
        Pid -> Pid ! {new_pair, Key, Value}
    end
.

% Check for new pairs to add to the value table
% and distribute them to the network.
% New pairs are received from the add_pair function
% using the receive statement with new_pair message
check_for_new_pairs(ValuesTable, RoutingTable, K, BucketSize) ->
    receive
        {new_pair, Key, Value} ->
            ets:insert(ValuesTable, {Key,Value}),
            node:distribute_value(Key, Value, RoutingTable, K, BucketSize)
    after 10 -> % This has to be 10 ms to avoid blocking the network
        ok
    end
.

% Every T seconds the republisher takes the ValuesMap and foreach 
% value it starts a store procedure
republish_behaviour(ValuesTable, RoutingTable, K, T, BucketSize, LastMillis) ->
    % Update verbosity
    thread:check_verbose(),
    ?MODULE:check_for_new_pairs(ValuesTable, RoutingTable, K, BucketSize),

    CurrentMillis = erlang:monotonic_time(millisecond),
    DeltaMillis = CurrentMillis - LastMillis,

    if DeltaMillis >= T ->
        % Republish every element in the value table
        ValueList = ets:tab2list(ValuesTable),
        lists:foreach(
            fun({Key,Value}) ->
                % Checking for new pairs while republishing the old ones
                ?MODULE:check_for_new_pairs(ValuesTable, RoutingTable, K, BucketSize),
                % Republishing old pairs
                node:distribute_value(Key, Value, RoutingTable, K, BucketSize)
            end,
            ValueList
        ),        
        NewMillis = erlang:monotonic_time(millisecond);
    true ->
        NewMillis = LastMillis
    end,

    % Repeat
    ?MODULE:republish_behaviour(ValuesTable, RoutingTable, K, T, BucketSize, NewMillis)
.