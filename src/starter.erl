% -----------------------------------------------------------------------------
% Module: starter
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-15
% Description: This module starts the kademlia network simulation.
% -----------------------------------------------------------------------------

- module(starter).

- export([start/0, registerShell/0, start_kademlia_network/4, test_dying_process/0, pick_random_pid/1]).
% This function is used to start the simulation
% It starts the analytics_collector and calls
% the test function to start Bootstraps
% bootstrsap nodes and Processes normal processes 
start() ->    
    analytics_collector:start(),
    ?MODULE:registerShell(),
    ?MODULE:test_dying_process().

% Join procedure is registered
% so that all the processes can
% avoid saving shell pid when 
% receiving a command from the shell
registerShell() ->
    ShellPid = whereis(shellPid),
    if(ShellPid == undefined) ->
        register(shellPid, self());
    true-> ok
    end.

start_kademlia_network(Bootstraps, Processes, K,T) ->
    lists:foreach(
        fun(_) ->
            node:start(K, T, true)
        end,
        lists:seq(1,Bootstraps)
    ),

    lists:foreach(
        fun(_) ->
            node:start(K, T, false)
        end,
        lists:seq(1,Processes)
    ).

test_dying_process() ->
    utils:print("Starting a Kademlia network with 1 bootstrap and 5 nodes~n"),
    utils:print("1 bit for the hash and 4000 millis for republishig~n"),
    start_kademlia_network(1, 5, 1, 4000),
    [BootstrapNode|_] = analytics_collector:get_bootstrap_list(),

    utils:print("Waiting some time to let the network converge~n"),
    timer:sleep(2000),
    {ok, RoutingTable} = node:get_routing_table(BootstrapNode),
    % Pick a random pid from the routing table
    RandomPid = ?MODULE:pick_random_pid(RoutingTable),

    utils:print("Current routing table of the bootstrap node [~p] : ~n~p~n",[BootstrapNode,RoutingTable]),
    utils:print("Killing a random process in the network [~p]~n",[RandomPid]),
    node:kill(RandomPid),
    utils:print("Asking bootstrap to store value so it tryes to contact [~p]~n",[RandomPid]),
    node:store(BootstrapNode,"foo", 0),
    {ok, NewRoutingTable} = node:get_routing_table(BootstrapNode),
    utils:print("New routing table of the bootstrap node [~p] : ~n~p~n",[BootstrapNode,NewRoutingTable])
.
    

% This function selects a random pid from the routing table.
pick_random_pid(RoutingTable) ->
    {_,NodeList} = lists:nth(rand:uniform(length(RoutingTable)), RoutingTable),
    case NodeList of
        [] -> undefined;
        _ ->
            {_, RandomPid} = lists:nth(rand:uniform(length(NodeList)), NodeList),
            RandomPid
    end.
