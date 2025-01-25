% -----------------------------------------------------------------------------
% Module: kademlia
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2025-01-25
% Description: This module manages Kademlia network.
% -----------------------------------------------------------------------------

-module(kademlia).

-export([start_enviroment/2, start_new_nodes/4, destroy/0, registerShell/0]).

% The shell pid is registered
% so that all the processes can
% avoid saving shell pid when 
% receiving a command from the shell
registerShell() ->
    ShellPid = whereis(shellPid),
    if (ShellPid == undefined) ->
        register(shellPid, self());
    true -> ok
    end
.

% This function is used to start the environment
% before starting the simulation
% It starts the analytics_collector and registers
% the shell pid
start_enviroment(K,T) ->
    ?MODULE:registerShell(),
    bootstrap_list_manager:start(),
    bootstrap_list_manager:wait_for_initialization(),
    analytics_collector:start(K,T),
    analytics_collector:wait_for_initialization()    
.


% This function starts the nodes that will join the kademlia network
start_new_nodes(Bootstraps, Nodes, K, T) ->

    case analytics_collector:location() of
        undefined ->
            ?MODULE:start_enviroment(K, T),
            CanStart = true;
        _ -> 
            utils:print("An existing enviroment has been found: "),
            case analytics_collector:get_simulation_parameters() of
                {ExistingK, _} ->
                    if(ExistingK /= K) ->
                        utils:print("~n[ERROR] -> Inconsistent K parameter. ~n"),
                        utils:print("Can't start new nodes with a different K value.~n~n"),
                        utils:print("(Existing) ~p =/= ~p (New K).~n", [ExistingK, K]),
                        utils:print("Please ensure the parameter K is consistent.~n~n"),
                        CanStart = false;
                    true ->
                        utils:print("adding nodes to the network.~n~n"),
                        CanStart = true
                    end;                    
                _ -> CanStart = false
            end
    end,    

    if CanStart ->
        utils:print("Starting ~p bootstrap nodes and ~p other nodes~n", [Bootstraps, Nodes]),
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
        );
    true ->
        ok
    end
.

% This function is used to destroy the simulation
% It kills all the processes and the analytics_collector
destroy() ->
    AllProcesses = analytics_collector:get_node_list(),
    lists:foreach(
        fun(Pid) ->
            node:kill(Pid)
        end,
        AllProcesses
    ),
    analytics_collector:kill(),
    bootstrap_list_manager:kill()
    % exit(self(),kill)
.

