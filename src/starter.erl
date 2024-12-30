% -----------------------------------------------------------------------------
% Module: starter
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-20
% Description: This module starts the kademlia network simulation.
% -----------------------------------------------------------------------------

- module(starter).

- export([start/0, registerShell/0, start_kademlia_network/4, test_dying_process/0, pick_random_pid/1,test_join_mean_time/0]).
- export([wait_for_network_to_converge/0, wait_for_progress/1, destroy/0, flush_finished/0]).
% This function is used to start the simulation
% It starts the analytics_collector and calls
% the test function to start Bootstraps
% bootstrsap nodes and Processes normal processes 
start() ->    
    analytics_collector:start(),
    ?MODULE:registerShell(),
    ?MODULE:test_join_mean_time().

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

start_kademlia_network(Bootstraps, Nodes, K,T) ->
    utils:print("Starting a Kademlia network with ~p bootstrap and ~p nodes~n", [Bootstraps,Nodes]),
    utils:print("~p bit for the hash and ~p millis for republishig~n~n",[K,T]),
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
        lists:seq(1,Nodes)
    ).

test_dying_process() ->
    BootstrapNodes = 1,
    Nodes = 5,
    K = 1,
    T = 4000,

    analytics_collector:listen_for(finished_join_procedure),

    ?MODULE:start_kademlia_network(BootstrapNodes, Nodes, K, T),
    [BootstrapNode|_] = analytics_collector:get_bootstrap_list(),


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

test_join_mean_time() ->
    BootstrapNodes = 10,
    Nodes = 5000,
    K = 5,
    T = 4000,
    analytics_collector:listen_for(finished_join_procedure),
    StartMillis = erlang:monotonic_time(millisecond),
    ?MODULE:start_kademlia_network(BootstrapNodes,Nodes,K,T),
    utils:print("Waiting for the network to converge~n"),
    ?MODULE:wait_for_network_to_converge(),
    EndMillis = erlang:monotonic_time(millisecond),
    Elapsed = EndMillis - StartMillis,
    utils:print("~nTotal time for the network with ~p nodes to converge: ~pms~n",[Nodes, Elapsed]),
    
    JoinMeanTime = analytics_collector:join_procedure_mean_time(),
    utils:print("Mean time for processes to join the network: ~pms~n",[JoinMeanTime]),

    analytics_collector:flush_join_events(),
    utils:print("~nStarting a new node to measure join time~n"),
    StartPMillis = erlang:monotonic_time(millisecond),
    Pid = node:start(K,T,false),
    receive
        {event_notification, _, _} ->
            EndPMillis = erlang:monotonic_time(millisecond),
            ElapsedP = EndPMillis - StartPMillis,
            utils:print("Time for new process to join the network: ~pms~n",[ElapsedP]),
            timer:sleep(2000),
            {ok, RoutingTable} = node:get_routing_table(Pid),
            utils:print("Current routing table of the new node [~p] : ~n~p~n",[Pid,RoutingTable])


    after 50000 ->
        utils:print("Waiting too long for process to join the network. Join process failed.~n")
    end

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
    % AllProcesses = analytics_collector:get_processes_list(),
    % lists:foreach(
    %     fun(Pid)->
    %         exit(Pid, kill)
    %     end,
    %     AllProcesses
    % ),
    % analytics_collector:kill(),
    % AllTables = ets:all(),
    % lists:foreach(fun(Table) -> ets:delete(Table) end, AllTables),
    exit(self(),kill).