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
    debug_find_node().

debug_find_node() ->
    PID = node:start(5, 4),
    PID1 = node:start(5, 4),
    PID2 = node:start(5, 4),
    PID3 = node:start(5, 4),
    PID4 = node:start(5, 4),
    gen_server:cast(PID,{save_node, PID1}),
    gen_server:cast(PID,{save_node, PID2}),
    gen_server:cast(PID2,{save_node, PID3}),
    gen_server:cast(PID3,{save_node, PID4}),
    node:send_request(PID,{store, utils:k_hash("5", 5)}).

% quit() ->
    % SystemPids = [self(), group_leader()],
    % Pids = [Pid || Pid <- processes(), not lists:member(Pid, SystemPids)],
    % lists:foreach(fun(Pid) ->
    %     catch exit(Pid, kill)
    % end, Pids),
    % ok.