% -----------------------------------------------------------------------------
% Module: starter
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module starts the kademlia network simulation.
% -----------------------------------------------------------------------------

- module(starter).

- export([start/0]).
- import(node, [talk/0]).

start() -> 
    PID = node:start(4, 4),
    io:format("~p~n", [PID]).

% quit() ->
    % SystemPids = [self(), group_leader()],
    % Pids = [Pid || Pid <- processes(), not lists:member(Pid, SystemPids)],
    % lists:foreach(fun(Pid) ->
    %     catch exit(Pid, kill)
    % end, Pids),
    % ok.