% -----------------------------------------------------------------------------
% Module: simulation
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2025-01-25
% Description: This module manages the simulation providing an interface
%              to interact and choose between different available tests.
% -----------------------------------------------------------------------------

-module(simulation).

-export([start/0, choose_test/0, start_test/1, choose_parameters/0]).
-export([start_simulation/4, start_simulation/5]).
-export([wait_for_network_to_converge/1, wait_for_progress/1, wait_for_stores/1]).
-export([enter_processes_to_kill/1,insert_positive_integer/1]).
-export([test_dying_process/0, pick_random_pid/1, test_join_mean_time/0,wait_for_progress/2]).
-export([test_lookup_meantime/0, wait_for_lookups/1, test_republisher/0]).

% This function is used to start the simulation
% It prints the welcome message and the list of tests
% that can be run.
start() ->

    RealMessageLength = utils:print_centered_rectangle(["KADEMLIA NETWORK SIMULATION"]),
    utils:print_centered_rectangle(["Authors:", "Nunzio D'Amore", "Francesco Pio Rossi"], RealMessageLength),
    utils:print("~nChoose between the following tests:~n"),
    utils:print("1. Test dying process~n"),
    utils:print("2. Test join mean time~n"),
    utils:print("3. Test lookup mean time~n"),
    utils:print("4. Test republisher~n"),
    utils:print("5. Exit~n"),
    ?MODULE:choose_test()
.


% This function is used to choose the test to run
% based on the user input.
% It is a recursive function that asks the user to
% choose a test until a valid choice is made.
choose_test() ->
    Choice = io:get_line("Please enter the number of the test you want to run: "),
    utils:print("~n"),
    case string:trim(Choice) of
        "1" -> ?MODULE:start_test(fun ?MODULE:test_dying_process/0);
        "2" -> ?MODULE:start_test(fun ?MODULE:test_join_mean_time/0);
        "3" -> ?MODULE:start_test(fun ?MODULE:test_lookup_meantime/0);
        "4" -> ?MODULE:start_test(fun ?MODULE:test_republisher/0);
        "5" -> ok;
        _ -> utils:print("Invalid choice~p~n", [Choice]),
            ?MODULE:choose_test()
    end
.

% This function is used to make the user choose
% between the test with a large number of node 
% or a smaller network
choose_parameters() ->
    utils:print("Please choose which network you want to use. ~n"),

    AvailableNetworks = [
        {10, 8000, 5},
        {10, 4000, 5},
        {10, 2000, 5},
        {5, 1000, 5},
        {2, 500, 4},
        {1, 250, 3}
    ],

    % Visualizing available choice
    lists:foldl(
        fun({Bootstrap, Nodes, K}, Index) ->
            utils:print("~p. ~p bootstrap - ~p nodes - K = ~p~n",[Index, Bootstrap, Nodes, K]),
            Index + 1
        end,
        1,
        AvailableNetworks    
    ),

    Choice = io:get_line("Please enter the number of you choice: "),
    utils:print("~n"),

    TrimmedChoice = string:trim(Choice),

    case string:to_integer(TrimmedChoice) of
        {Index, []} -> 
            try
                lists:nth(Index, AvailableNetworks)
            catch _:_ ->
                utils:print("Invalid choice: ~p~n", [TrimmedChoice]),
                ?MODULE:choose_parameters()
            end;
        _ -> 
            utils:print("Invalid choice: ~p~n", [TrimmedChoice]),
            ?MODULE:choose_parameters()
    end
.


start_test(TestFunction) ->
    % Check if the analytics_collector is already started
    case analytics_collector:location() of
        undefined -> ok;
        _ -> 
            % If it is already started, we need to kill it
            % to avoid conflicts with the new test
            utils:print("Cleaning up the environment before starting the test...~n~n"),
            kademlia:destroy()
    end,
    TestFunction()
.


% This function starts a Kademlia simulation by
% starting the simulation enviroment and waiting for network
% to converge.
% To start the simulation it will use the specified parameters:
%   - Bootstraps: number of bootstrap nodes in the network
%   - Nodes: number of normal nodes in the network
%   - K: number of bits of the hash ids
%   - T: milliseconds before republishing
%   - EventsToListen: lists of events type to listen to during
%                     the simulation
start_simulation(Bootstraps, Nodes, K, T) ->
    ?MODULE:start_simulation(Bootstraps, Nodes, K, T, [])
.
start_simulation(Bootstraps, Nodes, K, T, EventsToListen) ->

    kademlia:start_enviroment(K, T),
    % Subscribing to finished_filling_routing_table 
    % to listen for network convergence
    analytics_collector:listen_for(finished_filling_routing_table),

    % Subscribing to specified events
    lists:foreach(
        fun(EventType) ->
            analytics_collector:listen_for(EventType)
        end,
        EventsToListen    
    ),

    % Starting the network
    kademlia:start_new_nodes(Bootstraps, Nodes, K, T),

    utils:print("Waiting for the network to converge~n"),
    TotalNodes = Nodes + Bootstraps,
    ?MODULE:wait_for_network_to_converge(TotalNodes),
    ok
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
    BootstrapNodes = 1,
    Nodes = 5,
    K = 1,
    T = 40000,

    utils:print_centered_rectangle(["Test dying process"]),

    ?MODULE:start_simulation(
        BootstrapNodes, 
        Nodes, 
        K, 
        T, 
        [stored_value]
    ),
    [BootstrapNode|_] = kademlia_enviroment:get_bootstrap_list(),
    
    
    utils:print("~nRequiring routing table to the bootstrapnode[~p]...~n",[BootstrapNode]),
    {ok, RoutingTable} = node:get_routing_table(BootstrapNode),

    utils:print("Current routing table of the bootstrap node [~p] : ~n",[BootstrapNode]),
    utils:print_routing_table(RoutingTable),

    % Pick a random pid from the routing table
    RandomPid = ?MODULE:pick_random_pid(RoutingTable),
    utils:print("~nKilling a random process in the network [~p]~n",[RandomPid]),
    node:kill(RandomPid),

    utils:print("~nAsking bootstrap to store value so it tries to contact [~p]~n",[RandomPid]),
    node:distribute(BootstrapNode,"foo", 0),
    
    ?MODULE:wait_for_stores(Nodes),
    
    {ok, NewRoutingTable} = node:get_routing_table(BootstrapNode),
    utils:print("~n~nNew routing table of the bootstrap node [~p] : ~n~n",[BootstrapNode]),
    utils:print_routing_table(NewRoutingTable)
.

% This test shows the network convergence time and 
% the nodes join mean time during and after network
% convergence
test_join_mean_time() ->
    utils:print_centered_rectangle(["Test join mean time"]),


    {BootstrapNodes, Nodes, K} = choose_parameters(), 
    T = 2000,

    StartMillis = erlang:monotonic_time(millisecond),
    ?MODULE:start_simulation(BootstrapNodes, Nodes, K, T),

    EndMillis = erlang:monotonic_time(millisecond),
    Elapsed = EndMillis - StartMillis,
    utils:print("~nTotal time for the network with ~p nodes to converge: ~pms~n",[Nodes, Elapsed]),
    

    JoinMeanTime = analytics_collector:join_procedure_mean_time(),
    utils:print("Mean time for processes to join the network: ~pms~n",[JoinMeanTime]),
    FillMeanTime = analytics_collector:filling_routing_table_mean_time(),
    utils:print("Mean time for processes to fill the routing table: ~pms~n",[FillMeanTime]),


    [{FirstFinished,_,_} | _] = analytics_collector:get_finished_filling_routing_table_nodes(),
    {ok,RoutingTable} = node:get_routing_table(FirstFinished),

    utils:print("~n~nRouting table of the first node (~p) that finished to fill its routing table: ~n",[FirstFinished]),
    utils:print_routing_table(RoutingTable),

    analytics_collector:flush_join_events(),
    analytics_collector:flush_filling_routing_table_events(),
    NewNodes = 250,
    utils:print("~nStarting ~p new nodes to measure join time~n", [NewNodes]),

    lists:foreach(
        fun(_) ->
            node:start(K, T, false)
        end,
        lists:seq(1, NewNodes)
    ),

    utils:print("Waiting for new nodes to converge~n"),
    ?MODULE:wait_for_network_to_converge(NewNodes),
    

    JoinMeanTimeNewP = analytics_collector:join_procedure_mean_time(),
    utils:print("Mean time for new processes to join the network: ~pms~n",[JoinMeanTimeNewP]),
    FillMeanTimeP = analytics_collector:filling_routing_table_mean_time(),
    utils:print("Mean time for new processes to fill the routing table: ~pms~n",[FillMeanTimeP])
.

enter_processes_to_kill(Max) ->
    Input = io:get_line("Please enter the number of nodes that stored the value to kill (from 1 to " ++ integer_to_list(Max) ++ ") : "),
    try
        case string:to_integer(string:trim(Input)) of
            {Value, _} when Value >= 1, Value =< Max -> Value;
            _ -> 
                utils:print("Invalid input.~n"),
                enter_processes_to_kill(Max)
        end
    catch _:_ ->
        utils:print("Invalid input.~n"),
        enter_processes_to_kill(Max)
    end
.

test_lookup_meantime() ->
    T = 3000000, % This has to be big so it doesnt 
                 % interfere with the simulation

    utils:print_centered_rectangle(["Test lookup mean time"]),

    {BootstrapNodes, Nodes, K} = choose_parameters(),

    ?MODULE:start_simulation(
        BootstrapNodes, 
        Nodes, 
        K, 
        T, 
        [finished_lookup, stored_value]
    ),

    utils:print("~nSaving 'foo' => 0 in the network...~n"),
    [BootstrapNode | _] = kademlia_enviroment:get_bootstrap_list(),
    node:distribute(BootstrapNode,"foo", 0),
    % Waiting to make sure the value is delivered
    ?MODULE:wait_for_stores(20),
    DisrtibutionMeanTime = analytics_collector:distribute_mean_time(),
    utils:print("~nDistribution mean time ~pms~n", [DisrtibutionMeanTime]),

    Lookups = 5,
    utils:print("~n~nExecuting ~p lookups for 'foo'~n",[Lookups]),
    ?MODULE:wait_for_lookups(Lookups),
    
    LookupMeanTime = analytics_collector:lookup_mean_time(),
    utils:print("~nMean time for lookup: ~pms~n",[LookupMeanTime]),

    analytics_collector:flush_lookups_events(),

    utils:print("~n~nGetting the nodes that stored 'foo'...~n"),
    NearestNodes = analytics_collector:get_nodes_that_stored("foo"),

    utils:print("Node that stored foo: ~p~n", [NearestNodes]),

    LenNearestNodes = length(NearestNodes),
    Max = LenNearestNodes - 1,
    NodesToKill = enter_processes_to_kill(Max),
        
    utils:print("Killing ~p nodes...~n", [NodesToKill]),
    lists:foreach(
        fun(I) ->
            NearNode = lists:nth(I, NearestNodes),
            node:kill(NearNode)
        end,  
        lists:seq(1, NodesToKill)
    ),

    utils:print("~nExecuting ~p lookups for 'foo'~n",[Lookups]),
    ?MODULE:wait_for_lookups(Lookups),
    LookupMeanTime2 = analytics_collector:lookup_mean_time(),
    utils:print("~nMean time for lookup after killing ~p nodes near 'foo': ~pms~n",[NodesToKill, LookupMeanTime2])
.

test_republisher() ->
    T = 2000,

    utils:print_centered_rectangle(["Test republisher"]),

    {BootstrapNodes, Nodes, K} = choose_parameters(),

    ?MODULE:start_simulation(BootstrapNodes, Nodes, K, T, [stored_value]),
    

    [BootstrapNode | _] = kademlia_enviroment:get_bootstrap_list(),
    utils:print("~nSaving 'foo' => 0 in the network with node ~p...~n", [BootstrapNode]),
    node:distribute(BootstrapNode,"foo", 0),    
    ?MODULE:wait_for_stores(20),
    DisrtibutionMeanTime = analytics_collector:distribute_mean_time(),
    utils:print("~nDistribution mean time ~pms~n", [DisrtibutionMeanTime]),

    utils:print("~n~nGetting the nodes that stored 'foo'...~n"),
    NearestNodes = analytics_collector:get_nodes_that_stored("foo"),

    utils:print("Node that stored foo: ~p~n", [NearestNodes]),

    LenNearestNodes = length(NearestNodes),
    NodesToKill = LenNearestNodes - 1,
    utils:print("Killing ~p nodes...~n", [NodesToKill]),
    lists:foreach(
        fun(I) ->
            NearNode = lists:nth(I, NearestNodes),
            % Ping1=node:ping(NearNode),
            % utils:print("~p~n",[Ping1]),
            node:kill(NearNode)
            % Ping2=node:ping(NearNode),
            % utils:print("~p~n",[Ping2])
        end,  
        lists:seq(1, NodesToKill)
    ),
    
    OnlyNodeAlive = lists:nth(20, NearestNodes),
    
    utils:print("~nOnly node that stored 'foo' alive: ~p~n", [OnlyNodeAlive]),

    analytics_collector:flush_nodes_that_stored(),
    utils:print("~nWaiting for new nodes to receive the value~n"),
    ?MODULE:wait_for_stores(20),

    NewNearestNodes = analytics_collector:get_nodes_that_stored("foo"),

    utils:print("~nNew nodes storing foo: ~p~n", [NewNearestNodes])
.  

% --------------------------------------
% TEST TOOLS
% --------------------------------------

% This function selects a random pid from the routing table.
pick_random_pid(RoutingTable) ->
    {_, NodeList} = lists:nth(rand:uniform(length(RoutingTable)), RoutingTable),
    case NodeList of
        [] -> undefined;
        _ ->
            {_, RandomPid} = lists:nth(rand:uniform(length(NodeList)), NodeList),
            RandomPid
    end
.

wait_for_stores(Stores) ->
    utils:print_progress(0, false),
    ?MODULE:wait_for_progress(
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
    )
.

% This function is used to wait for a number of lookups.
% It waits for the event system to notify the end of the lookups-
wait_for_lookups(Lookups) ->
    utils:print_progress(0, false),

    % Creating the function to compute the progress
    Fun = fun(F) ->
        RandomBootstrap = routing_table_filler:pick_bootstrap(),
        
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

    ?MODULE:wait_for_progress(
        fun() -> Fun(Fun) end,
        false
    )
.

% This function waits for the network to converge
% based on the event system of the analytics_collector
% waiting for finished_filling_routing_table event
%
% call analytics_collector:listen_for(finished_filling_routing_table)
% before calling wait_for_network_to_converge
wait_for_network_to_converge(Started) -> 
    utils:print_progress(0, true),   
    ?MODULE:wait_for_progress(
        fun() ->
            receive
                {event_notification, finished_filling_routing_table, _} ->
                    Finished = analytics_collector:get_finished_filling_routing_table_nodes(),
                    Progress = length(Finished) / Started,
                    Progress
            end
        end
    ),
    utils:print("~n")
.

% This function is used to wait for a task to end
% visualizing a progress bar based on Progress.
% Progress is a function used to compute the current progress.
% The function ends when Progress reaches 1.
wait_for_progress(Progress) ->
    ?MODULE:wait_for_progress(Progress, true).

wait_for_progress(Progress, PrintBar) -> 
    CurrentProgress = Progress(),
    utils:print_progress(CurrentProgress, PrintBar),
    if CurrentProgress == 1 ->
        ok;
    true ->
        ?MODULE:wait_for_progress(Progress, PrintBar)
    end
.

insert_positive_integer(Message) -> 
    Input = io:get_line(Message),
    try
        case string:to_integer(string:trim(Input)) of
            {Value, []} when Value >= 1 -> Value;
            _ -> 
                utils:print("Invalid input: Insert a positive integer.~n"),
                ?MODULE:insert_positive_integer(Message)
        end
    catch _:_ ->
        utils:print("Invalid input: Insert a positive integer.~n"),
        ?MODULE:insert_positive_integer(Message)
    end
.
