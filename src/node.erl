% -----------------------------------------------------------------------------
% Module: node
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module manages the node behaviour.
% -----------------------------------------------------------------------------

-module(node).
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2]).
-export([start/2, send_request/3, ping_node/1, store_value/5]).

% Starts a new node in the Kademlia network.
% K -> Number of bits to represent a node ID.
% T -> Time interval for republishing data.
% Returns the process identifier (PID) of the newly created node.
start(K, T) ->
    start_link(K, T)
.

% Starts the node process.
% gen_server:start_link/3 calls init/1, who takes in input [K, T].
start_link(K, T) ->
    {ok, Pid} = gen_server:start_link(?MODULE, [K, T], []),
    Pid
.

% Initializes the state of the node when it is created.
% Creates one ETS table and a map:
% - RoutingTable: Used to store the routing information of the node.
% - ValuesMap: Used to store key-value pairs managed by the node.
init([K, T]) ->
    % Generate a unique integer to create distinct ETS table names for each node.
    UniqueInteger = integer_to_list(erlang:unique_integer([positive])),    
    % Create unique table name for routing by appending the unique integer.
    RoutingName = list_to_atom("routing_table" ++ UniqueInteger),
    % Initialize ETS table with the specified properties.
    RoutingTable = ets:new(RoutingName, [set, private]),
    % Initialize ValuesTable as an empty map.
    ValuesTable = #{},
    % Define the bucket size for routing table entries.
    Bucket_Size = 20,
    % Return the initialized state, containing ETS tables and configuration parameters.
    {ok, {RoutingTable, ValuesTable, K, T, Bucket_Size}}
.

%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                     %%%
%%% AUSILIARY FUNCTIONS %%%
%%%                     %%%  
%%%%%%%%%%%%%%%%%%%%%%%%%%%

% This function is used to get the hash id of the node starting from his pid.
my_hash_id(K) ->
    PidString = pid_to_list(self()),
    utils:k_hash(PidString, K)
.

% Saves the information about a node into the routing table.
% NodePid: The process identifier of the node to be saved. It is used to contact the node.
% RoutingTable: the table where store the information.
% K: The number of bits used for the node's hash_id representation.
save_node(NodePid, RoutingTable, K, K_Bucket_Size) ->
    % Compute the hash ID of the node to memorize starting from its pid.
    NodeHashId = utils:k_hash(NodePid, K),
    % Determine the branch ID in the routing table corresponding to the hash ID.
    BranchID = utils:get_subtree_index(NodeHashId, my_hash_id(K)),
    % Check if the branch ID already exists in the routing table.
    case ets:lookup(RoutingTable, BranchID) of
        % If the branch doesn't exist, create a new list for this branch.
        [] -> 
            % Insert the new node into a fresh list and store it in the table.
            NewList = [{NodeHashId, NodePid}],
            ets:insert(RoutingTable, {BranchID, NewList});  
        % If the branch exists in the routing table, update the list of nodes
        % in that branch.
        [{BranchID, NodeList}] -> 
            if
                length(NodeList) < K_Bucket_Size ->
                    % If there is space within the K_bucket, we can add the informations
                    % about the new node without problems on the tail of the list.
                    NewNodeList = NodeList ++ [{NodeHashId, NodePid}],
                    % The routing table is a set, so the old list is overwritten by the
                    %  new one.
                    ets:insert(RoutingTable, {BranchID, NewNodeList});
                % If the k_bucket size is full, we check whether the element at the top 
                % of the list is still active.
                length(NodeList) == K_Bucket_Size -> 
                    [{LastSeenNodeHashId, LastSeenNodePid} | Tail] = NodeList,
                    case ping_node(LastSeenNodePid) of 
                        % If we get pong, the last node seen is still active,
                        % so we descard the new node and the last seen node
                        % is moved to the tail.
                        pong -> 
                            UpdatedNodeList = Tail ++ [{LastSeenNodeHashId, LastSeenNodePid}], 
                            ets:insert(RoutingTable, {BranchID, UpdatedNodeList});
                        % If we receive a 'pang', the last seen node is no longer active, 
                        % so we eliminate it and the new node is moved to the tail.
                        pang -> 
                            UpdatedNodeList = Tail ++ [{NodeHashId, NodePid}],
                            ets:insert(RoutingTable, {BranchID, UpdatedNodeList})
                    end
            end
    end
.

% This function is used to lookup for the nodes list in a branch.
branch_lookup(RoutingTable, BranchId) ->
    case ets:lookup(RoutingTable, BranchId) of
        % Return a list if BranchId is found.
        [{BranchId, NodeList}] -> NodeList;
        % Return an empty list if BranchId is not found.
        [] -> [] 
    end
.

% This function is used to lookup for the K closest nodes starting from a branch.
% After checking the branch, the function checks the branches on the left and on the right
% till it finds K nodes or the end of the routing table.
% The function returns a list containing the K or more closest nodes.
lookup_for_k_nodes(RoutingTable, K_Bucket_Size, BranchID, K) ->
    % Start the recursive lookup from the initial state: 0 nodes found, initial index I=0.
    lookup_for_k_nodes(RoutingTable, 0, K_Bucket_Size, BranchID, K, 0)
.
% Main function that recursively searches for K closest nodes. NodesCount is the number
% of nodes collected so far. BranchID is the starting index for lookup. I is the current
% step or offset in the lookup process.
lookup_for_k_nodes(RoutingTable, NodesCount, K_Bucket_Size, BranchID, K, I) 
    when BranchID + I =< K; BranchID - I >= 0 , NodesCount < K_Bucket_Size ->
        % Look up nodes in the branch on the right (BranchID + I).
        % I = 0, so first we look within the starting branch.
        if 
            BranchID + I =< K ->
                NodesList = branch_lookup(RoutingTable, BranchID + I);
            true -> 
                NodesList = []
        end,
        % Get the size of NodesList.
        Len = length(NodesList),
        % Look up nodes in the branch on the left (BranchID - I).
        if 
            BranchID - I >= 0, Len < K_Bucket_Size, I > 0 ->
                OtherNodes = branch_lookup(RoutingTable, BranchID - I);        
            true -> 
                OtherNodes = []
        end,
        % Calculate the total number of nodes from both sides.
        Len2 = length(OtherNodes) + Len + NodesCount,
        % If the total number of nodes is at least K, stop the recursion.
        case Len2 >= K_Bucket_Size of
            true ->
                % Stop searching once K nodes are reached.
                OtherNodes2 = [];
            false ->
                % Otherwise, keep searching further.
                OtherNodes2 = lookup_for_k_nodes(RoutingTable, Len2, K_Bucket_Size, BranchID, K, I + 1)
        end,
        % Merge nodes from right and left branches.
        Result = NodesList ++ OtherNodes ++ OtherNodes2,
        Result;
% Base case: When the number of nodes found is greater than or equal to K
% or we've finished searching all relevant branches.
lookup_for_k_nodes(_, NodesCount, K_Bucket_Size, BranchID, K, I) 
    when NodesCount >= K_Bucket_Size orelse BranchID + I > K, BranchID - I < 0  ->
        % Return an empty list or result indicating no more nodes needed. 
        []
.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                            %%%
%%% HANDLE CALLS (SYNCHRONOUS) %%%
%%%                            %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 

% This function is used to send synchronous requests to a node.
% NodeId is the node to which the request is sent.
send_request(NodePid, Request, Timeout) ->
    gen_server:call(NodePid, Request, Timeout)
.

% Handling synchronous requests to the node.
% The sending node of the request is stored in the recipient's routing table.
handle_call(Request, From, State) ->
    % Extract the PID of the sender.
    {SenderPid, _} = From,   
    % Extract the routing table and other relevant state variables of the node.
    {RoutingTable, _, K, _, Bucket_Size} = State, 
    % Save the sender node in the routing table.
    save_node(SenderPid, RoutingTable, K, Bucket_Size),
    request_handler(Request, From, State)
.

% Handles a request to find the closest nodes to a given HashID.
% HashID: The identifier of the target node.
% State: The current state of the node, including the routing table.
request_handler({find_node, HashID}, _From, State) ->
    % Extract the routing table and other relevant state variables of the node.
    {RoutingTable, _, K, _, Bucket_Size} = State,
    % Determine which branch of the routing table to search based on the target HashID.
    BranchID = utils:get_subtree_index(HashID, my_hash_id(K)),
    % Look up the closest K nodes within the routing table.
    NodeList = lookup_for_k_nodes(RoutingTable, Bucket_Size, BranchID, K),
    % Sort the nodes by their distance to the target HashID.
    SortedNodeList = utils:sort_node_list(NodeList, HashID),
    % Select at most Bucket_Size nodes from the sorted list.
    if 
        length(SortedNodeList) > Bucket_Size -> 
            % Truncate to K nodes if the list is too long.
            K_NodeList = lists:sublist(SortedNodeList, K); 
        true -> 
            % Use the entire list if it's within the limit.
            K_NodeList = SortedNodeList 
    end,
    % Reply to the caller with the list of closest nodes and the current state.
    {reply, {ok, K_NodeList}, State};
% Handles the ping message sent to a node.
request_handler(ping, _From, State) ->
    % Reply with pong to indicate that the node is alive and reachable.
    {reply, pong, State};
    
% Handles any unrecognized request by replying with an error.
request_handler(_, _, State) ->
    {reply, not_handled_request, State}
.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                            %%%
%%% HANDLE CAST (ASYNCHRONOUS) %%%
%%%                            %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 

% A node store a key/value pair in its own values table.
% The node also saves the sender node in its routing table.
handle_cast({store, Key, Value, SenderPid}, State) ->
    {RoutingTable, ValuesTable, K, T, Bucket_Size} = State,
    NewValuesTable = maps:put(Key, Value, ValuesTable),
    NewState = {RoutingTable, NewValuesTable, K, T, Bucket_Size},
    save_node(SenderPid, RoutingTable, K, Bucket_Size),
    {noreply, NewState}
.

terminate(_Reason, _State) ->
    ok
.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                            %%%
%%%     NODE AS A CLIENT       %%%
%%%                            %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% Finds the K closest nodes in the network to a given HashID.
% The function starts by querying the local routing table for potential candidates.
% It then iteratively contacts nodes to refine the list of closest nodes.
iterate_find_node(RoutingTable, HashID, Bucket_Size, K) ->
    % Determine the branch in the routing table corresponding to the HashID.
    BranchID = utils:get_subtree_index(HashID, my_hash_id(K)),
    % Retrieve the initial list of closest nodes from the routing table.
    NodeMap = lookup_for_k_nodes(RoutingTable, Bucket_Size, BranchID, K),
    % Convert the node map to a list for processing.
    NodeList = utils:map_to_list(NodeMap),
    % Begin the recursive search to refine the closest node list.
    iterate_find_node(HashID, Bucket_Size, K, NodeList, [])
.
% Base case: If there are no more nodes to contact, return the sorted list of the K 
% closest nodes.
iterate_find_node(HashID, _, K, [], ContactedNodes) -> 
    % Sort the contacted nodes by proximity to the HashID and return the top K nodes.
    SortedNodeList = utils:sort_node_list(ContactedNodes, HashID),
    lists:sublist(SortedNodeList, K);
% Recursive case: Process the next node in the list of candidates.
iterate_find_node(HashID, Bucket_Size, K, [{NodeHash, NodePid}|T], ContactedNodes) ->
    % Log the node being contacted for debugging purposes.
    io:format("Contacting node: ~p~n", [NodePid]),
    % Send a request to the node to find its closest nodes to the HashID.
    case gen_server:call(list_to_pid(NodePid), {find_node, HashID}) of
        {ok, NodeList} ->
            % Filter the returned node list to exclude nodes already contacted or self.
            FilteredNodeList = lists:filter(
                fun(Node) -> 
                    {_, FilterPid} = Node,
                    not lists:member(Node, ContactedNodes) andalso
                    FilterPid /= pid_to_list(self())
                end, 
                NodeList
            ),
            % Combine the remaining nodes to process with the filtered nodes from the response.
            NewNodeList = lists:append(T, FilteredNodeList),
            % Add the current node to the list of contacted nodes.
            NewContactedNodes = lists:append(ContactedNodes, [{NodeHash, NodePid}]),
            % Recursively continue searching with the updated lists.
            Result = iterate_find_node(HashID, Bucket_Size, K, NewNodeList, NewContactedNodes);
        % If the request fails, skip the current node and continue with the rest.
        _ -> 
            Result = iterate_find_node(HashID, Bucket_Size, K, T, ContactedNodes)
    end,
    Result
.

% Pings a specific node (NodePid) to check its availability.
ping_node(NodePid) ->
    Timeout = 500, 
    try 
        % Send a synchronous call to the node with the message ping and the defined timeout.
        % Returns pong.
        send_request(NodePid, ping, Timeout)
    catch
        % Handle a timeout error, indicating the node did not respond in time.
        exit:{timeout, _} -> 
            io:format("Node ~p did not respond, returning 'pang'~n", [NodePid]),
            pang; 
        % Handle any other unexpected error during the call.
        _: _ -> 
            {error, unknown}
    end
.

% Client-side function to store a key/value pair in the K nodes closest
% to the hash_id of the pair.
store_value(Key, Value, RoutingTable, K, Bucket_Size) ->
    KeyHashId = utils:k_hash(Key, K),
    NodeList = iterate_find_node(RoutingTable, Key, KeyHashId, Bucket_Size, K),
    lists:foreach(
        fun({_NodeHashId, NodePid}) ->
            gen_server:cast(NodePid, {store, Key, Value, self()})
        end,
        NodeList
    )
.

% % Function to join the network. If no nodes exist, the actor becomes the bootstrap node.
% % Otherwise, it contacts the existing bootstrap node.
% join(RoutingTable, K) ->
%     case whereis(bootstrap) of
%         undefined -> 
%             % No existing nodes, become the bootstrap node.
%             register(bootstrap, self()),
%             % Register this node as the bootstrap node in the global registry.
%             % This way anyone knows the bootstrap and can join the network.
%             io:format("Node with pid ~p is the bootstrap node!~n", [self()]),
%             {bootstrap, self()};
%         BootstrapPid -> 
%             % The bootstrap node is saved within the routing table.
%             save_node(BootstrapPid, RoutingTable, K),
%             % Contact the existing bootstrap node to join the network
%             io:format("~p is joining the network by contacting the existing bootstrap node (~p)~n", 
%                 [self(), BootstrapPid]),
%             MyHashId = my_hash_id(K),
%             case send_request(BootstrapPid, {find_node, MyHashId}, infinity) of
%                 {ok, Nodes} ->
%                     % Nodes are saved in the routing table
%                     lists:foreach(
%                         fun({_, NodePid}) ->
%                             save_node(NodePid, RoutingTable, K)
%                         end, 
%                         Nodes
%                     ),
%                     io:format("Successfully joined the network. Updated routing table with nodes: ~p~n", [Nodes]),
%                     {ok, self()};
%                 Error ->
%                     io:format("Error while joining the network: ~p~n", [Error]),
%                     {error, Error}
%             end
%     end 
% .













