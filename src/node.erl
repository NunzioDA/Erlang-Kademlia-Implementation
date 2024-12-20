% -----------------------------------------------------------------------------
% Module: node
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module manages the node behaviour.
% -----------------------------------------------------------------------------

- module(node).
- behaviour(gen_server).

- export([start/0, handle_call/3, handle_cast/2, init/1, terminate/2, send_request/2]).

% This function is used to start a new node.
% It returns the PID of the new node.
start() ->
    start_link().

% This function starts the gen_server.
start_link() ->
    {ok, Pid} = gen_server:start_link(?MODULE, [], []),
    Pid.

% This function is used to get the hash id of the node.
my_hash_id() ->
    PidString = pid_to_list(self()),
    utils:k_hash(PidString, 160).

% This function is used to send a request to a node.
send_request(NodeID, Request) ->
    gen_server:call(NodeID, Request).

load_debug_data(RoutingTable,ValuesTable) ->
    save_node("cia1", RoutingTable, 4),
    save_node("cia2", RoutingTable, 4),
    save_node("cia3", RoutingTable, 4),
    save_node("cia4", RoutingTable, 4).

save_node(NodePid, RoutingTable, K) ->
    NodeHashId = utils:k_hash(NodePid, K),
    io:format("NodeHashId: ~p~n", [NodeHashId]),
    BranchID = utils:get_subtree_index(NodeHashId, my_hash_id()),
    
    case ets:lookup(RoutingTable, BranchID) of
        [] -> 
            NewMap = maps:put(NodeHashId, NodePid, #{}),
            ets:insert(RoutingTable, {BranchID, NewMap});
        [{BranchID, Map}] -> 
            NewMap = maps:put(NodeHashId, NodePid, Map),
            ets:insert(RoutingTable, {BranchID, NewMap})
    end.

% This function initializes the state of the gen_server
% creating the routing table and the values table.
init([]) ->
    RoutingTable = ets:new(routing_table, [set, private]),
    ValuesTable = ets:new(value_table, [set, private]),
    load_debug_data(RoutingTable,ValuesTable), 
    {ok, {RoutingTable, ValuesTable}}. 


handle_call({find_node, HashID}, _, State) ->
    {RoutingTable,_} = State,
    BranchID = utils:get_subtree_index(HashID, my_hash_id()),
    NodeList = ets:lookup(RoutingTable, BranchID),   
    
    {reply, {ok, NodeList}, State}.

handle_cast({store}, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.




