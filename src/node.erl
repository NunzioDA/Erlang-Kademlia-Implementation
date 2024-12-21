% -----------------------------------------------------------------------------
% Module: node
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module manages the node behaviour.
% -----------------------------------------------------------------------------

- module(node).
- behaviour(gen_server).

- export([start/2, handle_call/3, handle_cast/2, init/1, terminate/2, send_request/2, merge_nodes_maps/2]).

% This function is used to start a new node.
% It returns the PID of the new node.
start(K,T) ->
    start_link(K,T).

% This function starts the gen_server.
start_link(K,T) ->
    {ok, Pid} = gen_server:start_link(?MODULE, [K,T], []),
    Pid.

% This function is used to get the hash id of the node.
my_hash_id(K) ->
    PidString = pid_to_list(self()),
    utils:k_hash(PidString, K).

% This function is used to send a request to a node.
send_request(NodeID, Request) ->
    gen_server:call(NodeID, Request).

load_debug_data(RoutingTable,_) ->
    save_node("cia1", RoutingTable, 4),
    save_node("cia2", RoutingTable, 4),
    save_node("cia3", RoutingTable, 4),
    save_node("cia4", RoutingTable, 4).

% This function is used to save a node in the routing table.
save_node(NodePid, RoutingTable, K) ->
    NodeHashId = utils:k_hash(NodePid, K),

    BranchID = utils:get_subtree_index(NodeHashId, my_hash_id(K)),
    
    % Check if the branch is already present in the routing table
    case ets:lookup(RoutingTable, BranchID) of
        % If the branch is not present, create a new map
        [] -> 
            NewMap = maps:put(NodeHashId, [NodePid], #{}),
            ets:insert(RoutingTable, {BranchID, NewMap});
        % If the branch is present, update the map
        [{BranchID, Map}] -> 
            case maps:is_key(NodeHashId, Map) of
                true -> 
                    NodeList = maps:get(NodeHashId, Map),
                    NewMap = maps:update(NodeHashId, [NodePid | NodeList], Map),
                    ets:insert(RoutingTable, {BranchID, NewMap});
                false ->
                    NewMap = maps:put(NodeHashId, [NodePid], Map),
                    ets:insert(RoutingTable, {BranchID, NewMap})
            end
    end.

% This function initializes the state of the gen_server
% creating the routing table and the values table.
init([K,T]) ->
    UniqueInteger = integer_to_list(erlang:unique_integer([positive])),
    RoutingName = list_to_atom("routing_table" ++ UniqueInteger),
    ValuesName = list_to_atom("values_table" ++ UniqueInteger),    
    
    RoutingTable = ets:new(RoutingName, [set, private]),
    ValuesTable = ets:new(ValuesName, [set, private]),
    load_debug_data(RoutingTable,ValuesTable), 
    {ok, {RoutingTable, ValuesTable, K, T}}. 

% This function is used to merge two nodes maps.
merge_nodes_maps(Map1, Map2) ->
    Map1Empty = maps:size(Map1) == 0,
    Map2Empty = maps:size(Map2) == 0,
    if  Map1Empty -> Map2;
        Map2Empty -> Map1;
        true -> 
            maps:fold(fun(Key, Value, AccMap) ->
                case maps:is_key(Key, AccMap) of
                    true -> 
                        maps:put(Key, lists:append(Value, maps:get(Key, AccMap)), AccMap);
                    false -> 
                        maps:put(Key, Value, AccMap)
                end
            end, Map1, Map2)
    end.

% This function is used to lookup for the nodes map in a branch.
branch_lookup(RoutingTable, BranchId) ->
    case ets:lookup(RoutingTable, BranchId) of
        [{_, NodeMap}] -> NodeMap;
        [] -> #{} 
    end.

% This function is used to lookup for the K closest nodes starting from a branch.
% After checking the branch, the function checks the branches on the left and on the right
% till it finds K nodes or the end of the routing table.
% The function returns a map containing the K closest nodes.
lookup_for_k_nodes(RoutingTable, K_Bucket_Size, BranchID, K) ->
    lookup_for_k_nodes(RoutingTable, 0, K_Bucket_Size, BranchID, K,0).

lookup_for_k_nodes(RoutingTable, NodesCount, K_Bucket_Size, BranchID, K, I) 
    when BranchID + I =< K, NodesCount < K_Bucket_Size orelse BranchID - I >= 0, NodesCount < K_Bucket_Size ->

    if BranchID + I =< K ->
        NodesMap = branch_lookup(RoutingTable, BranchID + I);
    true -> NodesMap = #{}
    end,

    Len = maps:size(NodesMap),

    if BranchID - I >= 0, Len < K_Bucket_Size, I > 0 ->
        OtherNodes = branch_lookup(RoutingTable, BranchID - I);        
    true -> OtherNodes = #{}
    end,

    Len2 = maps:size(OtherNodes) + Len + NodesCount,

    case Len2 >= K_Bucket_Size of
        true ->
            OtherNodes2 = #{};
        false ->
            OtherNodes2 = lookup_for_k_nodes(RoutingTable, Len2, K_Bucket_Size, BranchID, K, I + 1)
    end,

    Merge = merge_nodes_maps(NodesMap, OtherNodes),
    Result = merge_nodes_maps(Merge, OtherNodes2),

    Result;
lookup_for_k_nodes(_, NodesCount, K_Bucket_Size, BranchID, K, I) 
    when NodesCount>=K_Bucket_Size orelse BranchID + I > K, BranchID - I < 0  -> 
    #{}.


handle_call({find_node, HashID}, _, State) ->
    {RoutingTable,_, K, _} = State,
    K_Bucket_Size = 20,
    BranchID = utils:get_subtree_index(HashID, my_hash_id(K)),

    NodeList = lookup_for_k_nodes(RoutingTable, K_Bucket_Size, BranchID, K),
    
    {reply, {ok, NodeList}, State}.

handle_cast({store}, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.




