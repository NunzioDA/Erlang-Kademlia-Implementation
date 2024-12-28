% -----------------------------------------------------------------------------
% Module: starter
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-15
% Description: This module starts the kademlia network simulation.
% -----------------------------------------------------------------------------

- module(starter).

- export([start/2]).
% This function is used to start the simulation
% It starts the analytics_collector and calls
% the test function to start Bootstraps
% bootstrsap nodes and Processes normal processes 
start(Bootstraps, Processes) ->    
    analytics_collector:start(),
    registerShell(),
    test1(Bootstraps, Processes).

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

test1(Bootstraps, Processes) ->
    lists:foreach(
        fun(_) ->
            node:start(5, 4000, true)
        end,
        lists:seq(1,Bootstraps)
    ),

    lists:foreach(
        fun(_) ->
            node:start(5, 4000, false)
        end,
        lists:seq(1,Processes)
    ).
