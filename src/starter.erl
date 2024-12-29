% -----------------------------------------------------------------------------
% Module: starter
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-20
% Description: This module starts the kademlia network simulation.
% -----------------------------------------------------------------------------

- module(starter).

- export([start/0, registerShell/0, start_kademlia_network/4, test_dying_process/0, pick_random_pid/1]).
- export([wait_for_network_to_converge/0, wait_for_progress/1, destroy/0, flush_finished/0]).
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
    BootstrapNodes = 10,
    Nodes = 3000,
    K = 5,
    T = 4000,

    analytics_collector:listen_for(finished_join_procedure),
    utils:print("Starting a Kademlia network with ~p bootstrap and ~p nodes~n", [BootstrapNodes,Nodes]),
    utils:print("1 bit for the hash and 4000 millis for republishig~n~n"),
    ?MODULE:start_kademlia_network(BootstrapNodes, Nodes, K, T),
    [BootstrapNode|_] = analytics_collector:get_bootstrap_list(),

    node:talk(BootstrapNode),

    utils:print("Waiting for the network to converge~n"),
    ?MODULE:wait_for_network_to_converge(),
    
    utils:print("Requiring routing table to the bootstrapnode[~p]...~n",[BootstrapNode]),
    {ok, RoutingTable} = node:get_routing_table(BootstrapNode),

    utils:print("Current routing table of the bootstrap node [~p] : ~n~p~n",[BootstrapNode,RoutingTable]),

    % Pick a random pid from the routing table
    RandomPid = ?MODULE:pick_random_pid(RoutingTable),
    utils:print("Killing a random process in the network [~p]~n",[RandomPid]),
    node:kill(RandomPid),

    utils:print("Asking bootstrap to store value so it tryes to contact [~p]~n",[RandomPid]),
    node:store(BootstrapNode,"foo", 0),
    timer:sleep(2000),
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

flush_finished()->
    receive
        {event_notification, _, Event} ->
            utils:print("~p~n", [Event])
    after 5000 ->
        1
    end.
wait_for_network_to_converge() ->    
    wait_for_progress(
        fun() ->
            Unfinished = analytics_collector:get_unfinished_processes(),
            if length(Unfinished) > 0 ->
                receive
                    {event_notification, _, _} ->
                        Started = analytics_collector:get_started_join_processes(),
                        Finished = analytics_collector:get_finished_join_processes(),
                        Progress = length(Finished) / length(Started),
                        Progress
                after 50000 ->
                    1
                end;
            true -> 1
            end
        end
    ),
    utils:print("~n").

% This function is used to wait for a task to end
% visualizing a progress bar based on Progress.
% Progress is a function used to compute the current progress.
% The function ends when Progress reaches 1.
wait_for_progress(Progress) -> 
    CurrentProgress = Progress(),
    utils:print_progress(CurrentProgress),
    if CurrentProgress == 1 ->
        ok;
    true ->
        wait_for_progress(Progress)
    end.

destroy() ->
    AllProcesses = analytics_collector:get_processes_list(),
    lists:foreach(
        fun(Pid)->
            exit(Pid, kill)
        end,
        AllProcesses
    ),
    analytics_collector:kill().