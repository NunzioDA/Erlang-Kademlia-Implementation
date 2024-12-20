% -----------------------------------------------------------------------------
% Module: node
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module manages the node behaviour.
% -----------------------------------------------------------------------------

- module(node).
- behaviour(gen_server).

- export([start/0, handle_call/3, handle_cast/2, init/1, terminate/2]).

% This function is used to start a new node.
% It returns the PID of the new node.
start() ->
    start_link().

% This function starts the gen_server.
start_link() ->
    {ok, Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []),
    Pid.

% This function initializes the state of the gen_server
% creating the routing table and the values table.
init([]) ->
    RoutingTable = ets:new(routing_table, [set, public]),
    ValuesTable = ets:new(value_table, [set, public]),
    {ok, {RoutingTable, ValuesTable}}. 


handle_call({find_node, HashID}, _, State) ->
    {RoutingTable,_} = State,
    % TODO: implement the find_node function
    {reply, {ok}, State}.

handle_cast({store}, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.




