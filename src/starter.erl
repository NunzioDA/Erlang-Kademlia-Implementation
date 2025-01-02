% -----------------------------------------------------------------------------
% Module: starter
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-20
% Description: This module starts the Kademlia network simulation.
% -----------------------------------------------------------------------------

- module(starter).

- export([start/0, start_test_environment/0, registerShell/0, start_kademlia_network/4, test_dying_process/0, pick_random_pid/1, test_join_mean_time/0]).
- export([wait_for_network_to_converge/1, wait_for_progress/1, destroy/0, test_lookup_meantime/0, wait_for_lookups/1, test_republisher/0]).

% This function is used to start the simulation
% It prints the welcome message and the list of tests
% that can be run.
start() ->
    RealMessageLength = print_headline(["KADEMLIA NETWORK SIMULATION"]),
    print_headline(["Authors:","Nunzio D'Amore","Francesco Rossi"], RealMessageLength),
    utils:print("~nChoose between the following tests:~n"),
    utils:print("1. Test dying process~n"),
    utils:print("2. Test join mean time~n"),
    utils:print("3. Test lookup mean time~n"),
    utils:print("4. Test republisher~n"),
    utils:print("5. Exit~n"),
    choose_test().

% This function is used to choose the test to run
% based on the user input.
% It is a recursive function that asks the user to
% choose a test until a valid choice is made.
choose_test() ->
    Choice = io:get_line("Please enter the number of the test you want to run: "),
    utils:print("~n"),
    case string:trim(Choice) of
        "1" -> start_test(fun test_dying_process/0);
        "2" -> start_test(fun test_join_mean_time/0);
        "3" -> start_test(fun test_lookup_meantime/0);
        "4" -> start_test(fun test_republisher/0);
        "5" -> ok;
        _ -> utils:print("Invalid choice~p~n", [Choice]),
            choose_test()
    end.
start_test(TestFunction) ->
    % Check if the analytics_collector is already started
    case whereis(analytics_collector) of
        undefined -> ok;
        _ -> 
            % If it is already started, we need to kill it
            % to avoid conflicts with the new test
            utils:print("Cleaning up the environment before starting the test...~n~n"),
            destroy(),
            timer:sleep(1000) % Wait for the processes to die
    end,
    TestFunction().

% This function is used to start the environment
% before starting the simulation
% It starts the analytics_collector and registers
% the shell pid
start_test_environment() ->
    analytics_collector:start(),
    ?MODULE:registerShell()
.

% The shell pid is registered
% so that all the processes can
% avoid saving shell pid when 
% receiving a command from the shell
registerShell() ->
    ShellPid = whereis(shellPid),
    if (ShellPid == undefined) ->
        register(shellPid, self());
    true -> ok
    end.

% This function starts a Kademlia network with specified parameters:
%   - Bootstraps: number of bootstrap nodes in the network
%   - Nodes: number of normal nodes in the network
%   - K: number of bits of the hash ids
%   - T: milliseconds before republishing
start_kademlia_network(Bootstraps, Nodes, K, T) ->
    utils:print("Starting a Kademlia network with ~p bootstrap and ~p nodes~n", [Bootstraps, Nodes]),
    utils:print("~p bit for the hash and ~p millis for republishing~n~n", [K, T]),
    lists:foreach(
        fun(_) ->
            node:start(K, T, true)
        end,
        lists:seq(1, Bootstraps)
    ),
    lists:foreach(
        fun(_) ->
            node:start(K, T, false)
        end,
        lists:seq(1, Nodes)
    ).

% This function is used to destroy the simulation
% It kills all the processes and the analytics_collector
destroy() ->
    AllProcesses = analytics_collector:get_node_list(),
    lists:foreach(
        fun(Pid) ->
            exit(Pid, kill)
        end,
        AllProcesses
    ),
    analytics_collector:kill()
    % exit(self(),kill)
.

% -------------------------------------------------
% TESTS FUNCTION
% ------------------------------------------------- 
% 
% 
% test_dying_process shows how after a process dies
% as soon as other processes realize the node is not
% responding it is removed from the routing table
test_dying_process() ->
    start_test_environment(),
    BootstrapNodes = 1,
    Nodes = 5,
    K = 1,
    T = 40000,

    print_headline(["Test dying process"]),
    analytics_collector:listen_for(finished_join_procedure),
    analytics_collector:listen_for(stored_value),

    ?MODULE:start_kademlia_network(BootstrapNodes, Nodes, K, T),
    [BootstrapNode|_] = analytics_collector:get_bootstrap_list(),


    utils:print("Waiting for the network to converge~n"),
    TotalNodes = Nodes + BootstrapNodes,
    ?MODULE:wait_for_network_to_converge(TotalNodes),
    
    utils:print("~nRequiring routing table to the bootstrapnode[~p]...~n",[BootstrapNode]),
    {ok, RoutingTable} = node:get_routing_table(BootstrapNode),

    utils:print("Current routing table of the bootstrap node [~p] : ~n~p~n",[BootstrapNode,RoutingTable]),

    % Pick a random pid from the routing table
    RandomPid = ?MODULE:pick_random_pid(RoutingTable),
    utils:print("~nKilling a random process in the network [~p]~n",[RandomPid]),
    node:kill(RandomPid),

    utils:print("~nAsking bootstrap to store value so it tries to contact [~p]~n",[RandomPid]),
    node:distribute(BootstrapNode,"foo", 0),
    
    wait_for_stores(Nodes - 1),

    {ok, NewRoutingTable} = node:get_routing_table(BootstrapNode),
    utils:print("~n~nNew routing table of the bootstrap node [~p] : ~n~p~n",[BootstrapNode,NewRoutingTable])
.

% This test shows the network convergence time and 
% the nodes join mean time during and after network
% convergence
test_join_mean_time() ->
    start_test_environment(),
    BootstrapNodes = 10,
    Nodes = 8000,
    K = 5,
    T = 4000,

    print_headline(["Test join mean time"]),
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
    start_test_environment(),
    BootstrapNodes = 10,
    Nodes = 8000,
    K = 5,
    T = 3000000,

    print_headline(["Test lookup mean time"]),
    analytics_collector:listen_for(finished_join_procedure),
    analytics_collector:listen_for(finished_lookup),
    analytics_collector:listen_for(stored_value),

    ?MODULE:start_kademlia_network(BootstrapNodes,Nodes,K,T),

    utils:print("Waiting for the network to converge~n"),
    TotalNodes = Nodes + BootstrapNodes,
    ?MODULE:wait_for_network_to_converge(TotalNodes),

    utils:print("~nSaving 'foo' => 0 in the network...~n"),
    [BootstrapNode | _] = analytics_collector:get_bootstrap_list(),
    node:distribute(BootstrapNode,"foo", 0),
    % Waiting to make sure the value is delivered
    wait_for_stores(20),

    Lookups = 5,
    utils:print("~n~nExecuting ~p lookups for 'foo'~n",[Lookups]),
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
            node:kill(NearNode)
        end,  
        lists:seq(1, NodesToKill)
    ),

    NotKilled = lists:nth(20, NearestNodes),
    utils:print("~nNode not killed ~p~n",[NotKilled]),

    utils:print("~nExecuting ~p lookups for 'foo'~n",[Lookups]),
    wait_for_lookups(Lookups),
    LookupMeanTime2 = analytics_collector:lookup_mean_time(),
    utils:print("~nMean time for lookup after killing ~p nodes near 'foo': ~pms~n",[NodesToKill, LookupMeanTime2])
.

test_republisher() ->
    start_test_environment(),
    BootstrapNodes = 10,
    Nodes = 5000,
    K = 5,
    T = 5000,

    print_headline(["Test republisher"]),
    analytics_collector:listen_for(finished_join_procedure),
    analytics_collector:listen_for(stored_value),

    ?MODULE:start_kademlia_network(BootstrapNodes,Nodes,K,T),
    TotalNodes = Nodes + BootstrapNodes,
    ?MODULE:wait_for_network_to_converge(TotalNodes),

    [BootstrapNode | _] = analytics_collector:get_bootstrap_list(),
    utils:print("~nSaving 'foo' => 0 in the network with node ~p...~n", [BootstrapNode]),
    node:distribute(BootstrapNode,"foo", 0),


    wait_for_stores(20),
    utils:print("~n~nGetting the nodes that stored 'foo'...~n"),
    NearestNodes = analytics_collector:get_nodes_that_stored("foo"),

    utils:print("Node that stored foo: ~p~n", [NearestNodes]),

    LenNearestNodes = length(NearestNodes),
    NodesToKill = LenNearestNodes - 1,
    utils:print("Killing ~p nodes...~n", [NodesToKill]),
    lists:foreach(
        fun(I)->
            NearNode = lists:nth(I,NearestNodes),
            % Ping1=node:ping(NearNode),
            % utils:print("~p~n",[Ping1]),
            node:kill(NearNode)
            % Ping2=node:ping(NearNode),
            % utils:print("~p~n",[Ping2])
        end,  
        lists:seq(1, NodesToKill)
    ),
    
    OnlyNodeAlive = lists:nth(20,NearestNodes),
    
    utils:print("~nOnly node that stored 'foo' alive: ~p~n", [OnlyNodeAlive]),


    analytics_collector:flush_nodes_that_stored(),
    utils:print("~nWaiting for new nodes to receive the value~n"),
    wait_for_stores(20),

    NewNearestNodes = analytics_collector:get_nodes_that_stored("foo"),

    utils:print("~nNew nodes storing foo: ~p~n", [NewNearestNodes])

.  

% --------------------------------------
% TEST TOOLS
% --------------------------------------
%
center(String, Width) ->
    Padding = Width - length(String),
    LeftPadding = Padding div 2,
    RightPadding = Padding - LeftPadding,
    LeftSpaces = lists:duplicate(LeftPadding, $ ),
    RightSpaces = lists:duplicate(RightPadding, $ ),
    lists:concat([LeftSpaces, String, RightSpaces]).

% This function is used to print 
% the title.
% Content is a list of strings
print_headline(Content)->
    LongerString = lists:foldl(
        fun(String, Acc) ->
            if length(String) > Acc -> length(String);
            true -> Acc
            end
        end,
        0,
        Content
    ),
    MinMessageLength = 40,

    if LongerString > MinMessageLength ->
        RealMessageLength = LongerString;
    true ->
        RealMessageLength = MinMessageLength
    end,
    print_headline(Content, RealMessageLength).
print_headline(Content, RealMessageLength) ->    
    utils:print("+" ++ lists:duplicate(RealMessageLength, $-) ++ "+~n"),

    lists:foreach(
        fun(String) ->
            utils:print("|" ++ center(String, RealMessageLength) ++ "|~n")
        end,
        Content
    ),

    utils:print("+" ++ lists:duplicate(RealMessageLength, $-) ++ "+~n"),
    RealMessageLength.

% This function selects a random pid from the routing table.
pick_random_pid(RoutingTable) ->
    {_,NodeList} = lists:nth(rand:uniform(length(RoutingTable)), RoutingTable),
    case NodeList of
        [] -> undefined;
        _ ->
            {_, RandomPid} = lists:nth(rand:uniform(length(NodeList)), NodeList),
            RandomPid
    end.

wait_for_stores(Stores) ->
    utils:print_progress(0, false),
    wait_for_progress(
        fun() ->
            receive
                {event_notification, stored_value, _} ->
                    Finished = analytics_collector:get_nodes_that_stored("foo"),
                    Progress = length(Finished) / Stores,
                    Progress
            after 8000 ->
                1
            end
        end
    ).

% This function is used to wait for a number of lookups.
% It waits for the event system to notify the end of the lookups-
wait_for_lookups(Lookups)->
    utils:print_progress(0, false),

    % Creating the function to compute the progress
    Fun = fun(F) ->
        RandomBootstrap = join_thread:pick_bootstrap(),
        
        % checking if bootstrap is alive
        case erlang:is_process_alive(RandomBootstrap) of
            true -> % If it is alive, we can start the lookup
                node:lookup(RandomBootstrap,"foo", true),
                receive
                    {event_notification, finished_lookup, _} ->
                        Finished = analytics_collector:get_finished_lookup(),
                        LenFinished = length(Finished),
                        Progress = LenFinished / Lookups,
                        Progress
                after 20000 ->
                    utils:print("Failed to get lookup event with node ~p~n",[RandomBootstrap]),
                    1
                end;
            false -> F(F) % Recursive call to the function to pick a new bootstrap
        end
    end,

    wait_for_progress(
        fun() -> Fun(Fun) end,
        false
    ).

% This function waits for the network to converge
% based on the event system of the analytics_collector
% waiting for finished_join_procedure event
%
% call analytics_collector:listen_for(finished_join_procedure)
% before calling wait_for_network_to_converge
wait_for_network_to_converge(Started) -> 
    utils:print_progress(0, true),   
    wait_for_progress(
        fun() ->
            Unfinished = analytics_collector:get_unfinished_join_nodes(),
            if length(Unfinished) > 0 ->
                receive
                    {event_notification, finished_join_procedure, _} ->
                        Finished = analytics_collector:get_finished_join_nodes(),
                        Progress = length(Finished) / Started,
                        Progress
                after 8000 ->
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
    wait_for_progress(Progress, true).
wait_for_progress(Progress, PrintBar) -> 
    CurrentProgress = Progress(),
    utils:print_progress(CurrentProgress, PrintBar),
    if CurrentProgress == 1 ->
        ok;
    true ->
        wait_for_progress(Progress, PrintBar)
    end.
