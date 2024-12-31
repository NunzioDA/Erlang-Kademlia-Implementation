% -----------------------------------------------------------------------------
% Module: starter
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-20
% Description: This module starts the kademlia network simulation.
% -----------------------------------------------------------------------------

- module(starter).

- export([start/0, registerShell/0, start_kademlia_network/4, test_dying_process/0, pick_random_pid/1,test_join_mean_time/0]).
- export([wait_for_network_to_converge/1, wait_for_progress/1, destroy/0, test_lookup_meantime/0,wait_for_lookups/1]).

% This function is used to start the enviroment
% before starting the simulation
% It starts the analytics_collector and registers
% the shell pid
start() ->
    analytics_collector:start(),
    ?MODULE:registerShell()
.

% The shell pid is registered
% so that all the processes can
% avoid saving shell pid when 
% receiving a command from the shell
registerShell() ->
    ShellPid = whereis(shellPid),
    if(ShellPid == undefined) ->
        register(shellPid, self());
    true-> ok
    end.

% This function starts a kademlia network with specified parameters:
%   - Bootstraps: number of bootstrap nodes in the network
%   - Nodes: number of normal nodes in the network
%   - K: number of bits of the hash ids
%   - T: milliseconds before republishing
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

% -------------------------------------------------
% TESTS FUNCTION
% ------------------------------------------------- 
% 
% 
% test_dying_process shows how after a process dies
% as soon as other processes realize the node is not
% responding it is removed from the routing table
test_dying_process() ->
    start(),
    BootstrapNodes = 1,
    Nodes = 5,
    K = 1,
    T = 4000,

    analytics_collector:listen_for(finished_join_procedure),

    ?MODULE:start_kademlia_network(BootstrapNodes, Nodes, K, T),
    [BootstrapNode|_] = analytics_collector:get_bootstrap_list(),


    utils:print("Waiting for the network to converge~n"),
    ?MODULE:wait_for_network_to_converge(Nodes),
    
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

% get_join_values(X, Y) ->
%     analytics_collector:start(),
%     analytics_collector:listen_for(finished_join_procedure),
%     % BootstrapNodes = 10,
%     % Nodes = 2000,
%     K = 5,
%     T = 4000,
    
%     StartMillis = erlang:monotonic_time(millisecond),
%     ?MODULE:start_kademlia_network(X,Y,K,T),

%     utils:print("Waiting for the network to converge~n"),
%     ?MODULE:wait_for_network_to_converge(),

%     EndMillis = erlang:monotonic_time(millisecond),
%     Result = EndMillis - StartMillis,
%     utils:print("~nTotal time for the network with ~p nodes to converge: ~pms~n",[Y, Result]),
%     if(Y < 8000) ->
%         destroy(),
%         timer:sleep(2000),        
%         [Result | get_join_values(X*2, Y*2)];
%     true -> [Result]
%     end
% .
% This test shows the network convergence time and 
% the nodes join mean time during and after network
% convergence
test_join_mean_time() ->
    start(),
    BootstrapNodes = 10,
    Nodes = 8000,
    K = 5,
    T = 4000,

    analytics_collector:listen_for(finished_join_procedure),
    StartMillis = erlang:monotonic_time(millisecond),
    ?MODULE:start_kademlia_network(BootstrapNodes,Nodes,K,T),

    utils:print("Waiting for the network to converge~n"),
    TotalNodes = Nodes + BootstrapNodes,
    ?MODULE:wait_for_network_to_converge(TotalNodes),

    EndMillis = erlang:monotonic_time(millisecond),
    Elapsed = EndMillis - StartMillis,
    utils:print("~nTotal time for the network with ~p nodes to converge: ~pms~n",[Nodes, Elapsed]),
    
    JoinMeanTime = analytics_collector:join_procedure_mean_time(),
    utils:print("Mean time for each processes to join the network: ~pms~n",[JoinMeanTime]),

    analytics_collector:flush_join_events(),
    utils:print("~nStarting 5 new nodes to measure join time~n"),

    NewNodes = 5,
    lists:foreach(
        fun(_)->
            node:start(K,T,false)
        end,
        lists:seq(1,NewNodes)
    ),

    utils:print("Waiting for new nodes to converge~n"),
    ?MODULE:wait_for_network_to_converge(NewNodes),
    JoinMeanTimeNewP = analytics_collector:join_procedure_mean_time(),
    utils:print("Mean time for new processes to join the network: ~pms~n",[JoinMeanTimeNewP])
.

test_lookup_meantime() ->
    start(),
    BootstrapNodes = 10,
    Nodes = 8000,
    K = 5,
    T = 3000000,

    utils:print("TEST: Lookup mean time~n~n"),
    analytics_collector:listen_for(finished_join_procedure),
    analytics_collector:listen_for(finished_lookup),

    ?MODULE:start_kademlia_network(BootstrapNodes,Nodes,K,T),

    utils:print("Waiting for the network to converge~n"),
    TotalNodes = Nodes + BootstrapNodes,
    ?MODULE:wait_for_network_to_converge(TotalNodes),

    utils:print("~nSaving 'foo' => 0 in the network...~n"),
    [BootstrapNode | _] = analytics_collector:get_bootstrap_list(),
    node:store(BootstrapNode,"foo", 0),
    % Waiting to make sure the value is delivered
    timer:sleep(1000),

    Lookups = 5,
    utils:print("~nExecuting ~p lookups for 'foo'~n",[Lookups]),
    wait_for_lookups(Lookups),
    
    LookupMeanTime = analytics_collector:lookup_mean_time(),
    utils:print("~nMean time for lookup: ~pms~n",[LookupMeanTime]),


    analytics_collector:flush_lookups_events(),

    utils:print("~n~nGetting the nodes that stored 'foo'...~n"),
    NearestNodes = analytics_collector:get_nodes_that_stored("foo"),

    utils:print("Node that stored foo: ~p~n", [NearestNodes]),

    LenNearestNodes = length(NearestNodes),
    NodesToKill = LenNearestNodes - 1,
    utils:print("Killing ~p nodes...~n", [NodesToKill]),
    lists:foreach(
        fun(I)->
            NearNode = lists:nth(I,NearestNodes),
            % Ping1=node:ping_node(NearNode),
            % utils:print("~p~n",[Ping1]),
            node:kill(NearNode)
            % Ping2=node:ping_node(NearNode),
            % utils:print("~p~n",[Ping2])
        end,  
        lists:seq(1, NodesToKill)
    ),

    NotKilled = lists:nth(20, NearestNodes),
    utils:print("~nNode not killed ~p~n",[NotKilled]),

    utils:print("~nExecuting ~p lookups for 'foo'~n",[Lookups]),
    wait_for_lookups(Lookups),
    LookupMeanTime2 = analytics_collector:lookup_mean_time(),
    utils:print("~nMean time for lookup aftert killing ~p nodes near 'foo': ~pms~n",[NodesToKill, LookupMeanTime2])
.

% --------------------------------------
% TEST TOOLS
% --------------------------------------
%
% This function selects a random pid from the routing table.
pick_random_pid(RoutingTable) ->
    {_,NodeList} = lists:nth(rand:uniform(length(RoutingTable)), RoutingTable),
    case NodeList of
        [] -> undefined;
        _ ->
            {_, RandomPid} = lists:nth(rand:uniform(length(NodeList)), NodeList),
            RandomPid
    end.

wait_for_lookups(Lookups)->
    utils:print_progress(0),
    wait_for_progress(
        fun() ->
            RandomBootstrap = join_thread:pick_bootstrap(),
            Finished = analytics_collector:get_finished_lookup(),
            LenFinished = length(Finished) + 1,
            % Verbose = LenFinished == Lookups,
            node:find_value(RandomBootstrap,"foo", true),
            receive
                {event_notification, finished_lookup, _} ->
                    Progress = LenFinished / Lookups,
                    Progress
            after 20000 ->
                1
            end
        end
    ).

% This function waits for the network to converge
% based on the event system of the analytics_collector
% waiting for finished_join_procedure event
%
% call analytics_collector:listen_for(finished_join_procedure)
% before calling wait_for_network_to_converge
wait_for_network_to_converge(Started) -> 
    utils:print_progress(0),   
    wait_for_progress(
        fun() ->
            Unfinished = analytics_collector:get_unfinished_join_nodes(),
            if length(Unfinished) > 0 ->
                receive
                    {event_notification, _, _} ->

                        Finished = analytics_collector:get_finished_join_nodes(),
                        Progress = length(Finished) / Started,
                        Progress
                after 8000 ->
                    % utils:print("MAKE HIM TALK"),
                    % [First | _] = analytics_collector:get_unfinished_join_nodes(),
                    % node:talk(First),                    
                    % Processes = analytics_collector:get_node_list(),
                    % Hashes = lists:foldl(
                    %     fun(E, Acc) ->
                    %        [utils:to_bit_list(utils:k_hash(E,5))|Acc]
                    %     end,
                    %     [],
                    %     Processes    
                    % ),
                    % {ok, File} = file:open("../data/processes.txt", [write]),
                    % lists:foreach(fun(Pid) -> io:fwrite(File, "~p~n", [Pid]) end, Hashes),
                    % file:close(File),
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
    AllProcesses = analytics_collector:get_node_list(),
    lists:foreach(
        fun(Pid)->
            exit(Pid, kill)
        end,
        AllProcesses
    ),
    timer:sleep(2000),
    analytics_collector:kill()
    % exit(self(),kill)
.