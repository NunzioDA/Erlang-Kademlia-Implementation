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

    Bucket_Size = 20,
    {ok, {RoutingTable, ValuesTable, K, T, Bucket_Size}}. 

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
% The function returns a map containing the K or more closest nodes.
lookup_for_k_nodes(RoutingTable, K_Bucket_Size, BranchID, K) ->
    lookup_for_k_nodes(RoutingTable, 0, K_Bucket_Size, BranchID, K,0).

lookup_for_k_nodes(RoutingTable, NodesCount, K_Bucket_Size, BranchID, K, I) 
    when BranchID + I =< K; BranchID - I >= 0 , NodesCount < K_Bucket_Size ->
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

% This function is used to find the K closest nodes in the network to a given hash id.
% The function starts from the routing table and iterates over the branches to make requests
% to the nodes.
find_node(RoutingTable, HashID, Bucket_Size, K) ->
    BranchID = utils:get_subtree_index(HashID, my_hash_id(K)),
    NodeMap = lookup_for_k_nodes(RoutingTable, Bucket_Size, BranchID, K),
    NodeList = utils:map_to_list(NodeMap),
    find_node(HashID, Bucket_Size, K, NodeList, []).
find_node(HashID, _, K, [], ContactedNodes) -> 
    SortedNodeList = utils:sort_node_list(ContactedNodes, HashID),
    lists:sublist(SortedNodeList, K);
find_node(HashID, Bucket_Size, K, [{NodeHash, NodePid}|T], ContactedNodes) ->
    io:format("Contacting node: ~p~n", [NodePid]),
    case gen_server:call(list_to_pid(NodePid), {find_node, HashID}) of
        {ok, NodeList} ->
            FilteredNodeList = lists:filter(
                fun(Node) -> 
                    {_,FilterPid} = Node,
                    not lists:member(Node, ContactedNodes) andalso                    
                    FilterPid /= pid_to_list(self())
                end, 
                NodeList
            ),
            NewNodeList = lists:append(T, FilteredNodeList),

            NewContactedNodes = lists:append(ContactedNodes, [{NodeHash, NodePid}]),
            Result = find_node(HashID, Bucket_Size, K, NewNodeList, NewContactedNodes);
        _ -> 
            Result = find_node(HashID, Bucket_Size, K, T, ContactedNodes)
    end,
    Result.


handle_call({find_node, HashID}, _, State) ->
    {RoutingTable,_, K, _, Bucket_Size} = State,
   
    BranchID = utils:get_subtree_index(HashID, my_hash_id(K)),

    NodeMap = lookup_for_k_nodes(RoutingTable, Bucket_Size, BranchID, K),
    NodeList = utils:map_to_list(NodeMap),
    SortedNodeList = utils:sort_node_list(NodeList, HashID),
    if length(SortedNodeList) > Bucket_Size -> 
        K_NodeList = lists:sublist(SortedNodeList, K);
        true -> K_NodeList = SortedNodeList
    end,

    {reply, {ok, K_NodeList}, State};
% handle_call({store, HashId}, _, State) ->
%     {RoutingTable, _, K, _, Bucket_Size} = State,
%     io:format("Storing node with hash id: ~p~n", [HashId]),
%     Response = find_node(RoutingTable, HashId, Bucket_Size, K),
%     {reply, {ok, Response}, State};
handle_call(_, _, State) ->
    {reply, not_handled_request, State}.



handle_cast({store, _}, _) ->
    {ok, ok}.
% handle_cast({save_node, NodePid}, State) ->
%     {RoutingTable, _, K, _, _} = State,
%     io:format("Saving node: ~p~n", [NodePid]),
%     save_node(pid_to_list(NodePid), RoutingTable, K),
%     {noreply, State}.

terminate(_Reason, _State) ->
    ok.




