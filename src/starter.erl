% -----------------------------------------------------------------------------
% Module: starter
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module starts the kademlia network simulation.
% -----------------------------------------------------------------------------

- module(starter).

- export([start/1]).
- import(node, [talk/0]).

start(N) -> 
    register(shellPid, self()),
    debug_find_node(N).

debug_find_node(N) ->
    
    lists:foreach(
        fun(_) ->
            node:start(5, 4)
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