% -----------------------------------------------------------------------------
% Module: starter
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module starts the kademlia network simulation.
% -----------------------------------------------------------------------------

- module(starter).

- export([start/2]).

start(Bootstraps, Processes) -> 
    
    analytics_collector:start(),
    registerShell(),
    debug_find_node(Bootstraps, Processes).

registerShell() ->
    ShellPid = whereis(shellPid),
    if(ShellPid /= undefined) ->
        register(shellPid, self());
    true->ok
    end.

debug_find_node(Bootstraps, Processes) ->
    lists:foreach(
        fun(_) ->
            node:start(5, 4, true)
        end,
        lists:seq(1,Bootstraps)
    ),

    lists:foreach(
        fun(_) ->
            node:start(5, 4, false)
        end,
        lists:seq(1,Processes)
    ).

% quit() ->
    % SystemPids = [self(), group_leader()],
    % Pids = [Pid || Pid <- processes(), not lists:member(Pid, SystemPids)],
    % lists:foreach(fun(Pid) ->
    %     catch exit(Pid, kill)
    % end, Pids),
    % ok.