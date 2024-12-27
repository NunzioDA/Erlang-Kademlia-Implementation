% -----------------------------------------------------------------------------
% Module: starter
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module starts the kademlia network simulation.
% -----------------------------------------------------------------------------

- module(starter).

- export([start/1]).

start(N) -> 
    analytics_collector:start(),
    registerShell(),
    debug_find_node(N).

registerShell() ->
    ShellPid = whereis(shellPid),
    if(ShellPid /= undefined) ->
        register(shellPid, self());
    true->ok
    end.

debug_find_node(N) ->
    
    lists:foreach(
        fun(_) ->
            node:start(5, 4, false)
        end,
        lists:seq(0,N)
    ).

% quit() ->
    % SystemPids = [self(), group_leader()],
    % Pids = [Pid || Pid <- processes(), not lists:member(Pid, SystemPids)],
    % lists:foreach(fun(Pid) ->
    %     catch exit(Pid, kill)
    % end, Pids),
    % ok.