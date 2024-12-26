% -----------------------------------------------------------------------------
% Module: node
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module manages the node behaviour.
% -----------------------------------------------------------------------------

-module(node).
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, terminate/2]).
-export([start/2, start/3, send_request/2, ping_node/1, store_value/5, join/3, find_value/2, find_k_nearest_node/4, get_routing_table/1]).


% Starts a new node in the Kademlia network.
% K -> Number of bits to represent a node ID.
% T -> Time interval for republishing data.
% Returns the process identifier (PID) of the newly created node.
start(K, T) ->
    start(K, T, false)
.
start(K, T, Verbose) ->
    Pid = start_link(K, T, Verbose),
    Pid
.

% Starts the node process.
% gen_server:start_link/3 calls init/1, who takes in input [K, T].
start_link(K, T, Verbose) ->
    {ok, Pid} = gen_server:start_link(?MODULE, [K, T, Verbose], []),
    Pid
.

% Initializes the state of the node when it is created.
% Creates one ETS table and a map:
% - RoutingTable: Used to store the routing information of the node.
% - ValuesMap: Used to store key-value pairs managed by the node.
init([K, T, Verbose]) ->
    save_address(self()),
    set_verbose(Verbose),
    % Generate a unique integer to create distinct ETS table names for each node.
    UniqueInteger = integer_to_list(erlang:unique_integer([positive])),    
    % Create unique table name for routing by appending the unique integer.
    RoutingName = list_to_atom("routing_table" ++ UniqueInteger),
    % Initialize ETS table with the specified properties.
    RoutingTable = ets:new(RoutingName, [set, public]),
    % Initialize ValuesTable as an empty map.
    ValuesTable = #{},
    % Define the bucket size for routing table entries.
    Bucket_Size = 20,

    join(RoutingTable, K, Bucket_Size),

    % Return the initialized state, containing ETS tables and configuration parameters.
    {ok, {RoutingTable, ValuesTable, K, T, Bucket_Size}}
.

%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                     %%%
%%% AUSILIARY FUNCTIONS %%%
%%%                     %%%  
%%%%%%%%%%%%%%%%%%%%%%%%%%%

start_thread(Function) ->
    ParentAddress = my_address(),
    Verbose = utils:verbose(),
    spawn(
        fun()->
            % Saving parent address and verbose in the new process
            % so it can behave like the parent
            set_verbose(Verbose),
            save_address(ParentAddress),
            Function()
        end
    ).

% This function is used to get the hash id of the node starting from his pid.
my_hash_id(K) ->
    PidString = pid_to_list(my_address()),
    utils:k_hash(PidString, K)
.

% Saves the information about a node into the routing table.
% Save node is managed with a cast request so that it is not blocking
% for the call handling functions or else it would cause a timeout.
save_node(NodePid) -> 
    MyPid = my_address(),
    StringPid = pid_to_list(MyPid),

    % Save node avoids saving its own pid or the shell pid 
    if NodePid /= MyPid, NodePid /= StringPid ->
        ShellPid = whereis(shellPid),
        if NodePid /= ShellPid, NodePid /= undefined ->
            % gen_server:cast is used so save_node is not blocking
            % send_async_request is not used because save_node is handled separately
            gen_server:cast(my_address(), {save_node, NodePid});
        true -> {ignored_node, "Shell pid passed"}
        end;
    true -> {ignored_node, "Can't save my pid"}
    end
.
% NodePid: The process identifier of the node to be saved. It is used to contact the node.
% RoutingTable: the table where store the information.
% K: The number of bits used for the node's hash_id representation.
save_node(NodePid, RoutingTable, K, K_Bucket_Size) when is_pid(NodePid) ->
    save_node(pid_to_list(NodePid), RoutingTable, K, K_Bucket_Size);
save_node(NodePid, RoutingTable, K, K_Bucket_Size) when is_list(NodePid) ->
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
            % Check if the node is already in the list.
            case lists:keyfind(NodeHashId, 1, NodeList) of
                {_,_} ->
                    % If the node is already in the list, move it to the end
                    RemovedNodeList = lists:filter(fun(Element) -> Element =/= {NodeHashId, NodePid}end, NodeList),
                    NewNodeList = RemovedNodeList ++ [{NodeHashId, NodePid}],
                    ets:insert(RoutingTable, {BranchID, NewNodeList});
                % If the node is not in the list, add it to the tail.
                false -> 
                    % Check if the list is full or not.
                    case length(NodeList) < K_Bucket_Size of
                        % If the list is not full, add the new node to the tail.
                        true -> 
                            NewNodeList = NodeList ++ [{NodeHashId, NodePid}],
                            ets:insert(RoutingTable, {BranchID, NewNodeList});
                        % If the list is full, check the last node in the list.
                        false -> 
                            % Extract the last node in the list.
                            [{LastSeenNodeHashId, LastSeenNodePid} | Tail] = NodeList,
                            % Check if the last node is still responsive.
                            case ping_node(LastSeenNodePid) of 
                                % If the last node is responsive, discard the new node.
                                {pong, ok} -> 
                                    UpdatedNodeList = Tail ++ [{LastSeenNodeHashId, LastSeenNodePid}], 
                                    ets:insert(RoutingTable, {BranchID, UpdatedNodeList});
                                % If the last node is not responsive, discard it and add the new node.
                                {pang, _} -> 
                                    UpdatedNodeList = Tail ++ [{NodeHashId, NodePid}],
                                    ets:insert(RoutingTable, {BranchID, UpdatedNodeList})
                            end
                    end
            end
    end.


% This function is used to lookup for the nodes list in a branch.
branch_lookup(RoutingTable, BranchId) ->
    case ets:lookup(RoutingTable, BranchId) of
        % Return a list if BranchId is found.
        [{BranchId, NodeList}] -> NodeList;
        % Return an empty list if BranchId is not found.
        [] -> [] 
    end
.

% This function is used to lookup for the K closest nodes starting from a branch in local.
% After checking the current branch, the function checks the branches on the left and on the right
% till it finds K nodes or the end of the routing table.
% HashId is the target hash ID for which we are looking for the closest nodes.
% The function returns a list containing the K closest nodes to HashId.
find_node(RoutingTable, K_Bucket_Size, K, HashId) ->
    BranchID = utils:get_subtree_index(HashId, my_hash_id(K)),
    % Start the recursive lookup from the initial state: 0 nodes found, initial index I = 0.
    find_node(RoutingTable, 0, K_Bucket_Size, BranchID, K, HashId, 0)
.
% Main function that recursively searches for K closest nodes. NodesCount is the number
% of nodes collected so far. BranchID is the starting index for lookup. I is the current
% step or offset in the lookup process.
find_node(RoutingTable, NodesCount, K_Bucket_Size, BranchID, K, HashId, I) 
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
                OtherNodes2 = find_node(RoutingTable, Len2, K_Bucket_Size, BranchID, K, HashId, I + 1)
        end,
        % Merge nodes from right and left branches.
        Result = NodesList ++ OtherNodes ++ OtherNodes2,
        % Sort the nodes by their distance to the target HashID.
        SortedNodeList = utils:sort_node_list(Result, HashId),
        % Select at most Bucket_Size nodes from the sorted list.
        if 
            length(SortedNodeList) > K_Bucket_Size -> 
                % Truncate to K nodes if the list is too long.
                K_NodeList = lists:sublist(SortedNodeList, K_Bucket_Size); 
            true -> 
                % Use the entire list if it's within the limit.
                K_NodeList = SortedNodeList 
        end,
        K_NodeList;
% Base case: When the number of nodes found is greater than or equal to K
% or we've finished searching all relevant branches.
find_node(_, NodesCount, K_Bucket_Size, BranchID, K, _, I) 
    when NodesCount >= K_Bucket_Size orelse BranchID + I > K, BranchID - I < 0  ->
        % Return an empty list or result indicating no more nodes needed. 
        []
.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                            %%%
%%% HANDLE CALLS (SYNCHRONOUS) %%%
%%%                            %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 

handle_call({routing_table}, _From, State) ->
    {RoutingTable, _, _, _, _} = State,
    % Return = utils:print_routing_table(RoutingTable, my_hash_id(K)),
    {reply, {ok, ets:tab2list(RoutingTable)}, State};
% Handling synchronous requests to the node.
% The sending node of the request is stored in the recipient's routing table.
handle_call({Request, SenderPid}, _, State) ->  
    % Save the sender node in the routing table.
    save_node(SenderPid),
    request_handler(Request, SenderPid, State).

% Handles a request to find the closest nodes to a given HashID.
% HashID: The identifier of the target node.
% State: The current state of the node, including the routing table.
request_handler({find_node, HashID}, _From, State) ->
    % Extract the routing table and other relevant state variables of the node.
    {RoutingTable, _, K, _, Bucket_Size} = State,
    % Look up the closest K nodes within the routing table.
    NodeList = find_node(RoutingTable, Bucket_Size, K, HashID),
    % Reply to the caller with the list of closest nodes and the current state.
    {reply, {ok, NodeList}, State};
request_handler({find_value, Key}, _From, State) ->
    % Extract the routing table and other relevant state variables of the node.
    {RoutingTable, ValuesTable, K, _, Bucket_Size} = State,
    case maps:member(Key, ValuesTable) of 
        true -> 
            % If the key is found in the local values table, return the value.
            {reply, {ok, maps:get(Key, ValuesTable)}, State};
        false ->
            % Compute the hash ID of the key to search for.
            KeyHashId = utils:k_hash(Key, K),
            % If the key is not found, look up the closest K nodes to the key's hash ID.
            NodeList = find_node(RoutingTable, Bucket_Size, K, KeyHashId),
            % Reply with the list of closest nodes to the key.
            {reply, {ok, NodeList}, State}
    end;
% This request is used during the join operation to fill the routing table of the new node.
request_handler({fill_my_routing_table, FilledIndexes}, ClientPid, State) ->
    {RoutingTable, _, K, _, Bucket_Size} = State,
    % First the server finds all the branches that it shares with the client
    % making the filling procedue more efficient.
    ClientHash = utils:k_hash(pid_to_list(ClientPid), K),
    SubTreeIndex = utils:get_subtree_index(my_hash_id(K), ClientHash),

    AllBranches = lists:seq(0, SubTreeIndex),
    % The server avoids to lookup for the branches that the client have already filled.
    BranchesToLookup = lists:filter(
        fun(X) -> 
            not lists:member(X, FilledIndexes) andalso X =< SubTreeIndex            
        end, 
        AllBranches
    ),
    Branches = lists:foldl(
        fun(Branch, NodeList) ->
            BranchContent = branch_lookup(RoutingTable, Branch),
            NodeList ++ BranchContent
        end,
        [],
        BranchesToLookup
    ),
    % The server returns the nearest nodes to the client that are next to be requested.
    NearestNodes = find_node(RoutingTable, Bucket_Size, K, ClientHash),
    Response = {ok, {Branches, NearestNodes}},
    {reply, Response, State};

% Handles the ping message sent to a node.
request_handler(ping, From, State) ->
    utils:debugPrint("Ping received ~p~n", [From]),
    % Reply with pong to indicate that the node is alive and reachable.
    {reply, {pong, ok}, State};
% Handles any unrecognized request by replying with an error.
request_handler(_, _, State) ->
    {reply, not_handled_request, State}
.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                            %%%
%%% HANDLE CAST (ASYNCHRONOUS) %%%
%%%                            %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 

% When a save_node request is received save_node is called
handle_cast({save_node, NodePid}, State) ->
    {RoutingTable, _, K, _, Bucket_Size} = State,
    save_node(NodePid, RoutingTable, K, Bucket_Size),
    {noreply, State};

handle_cast({Request, SenderPid}, State) when is_tuple(Request) ->
    
    save_node(SenderPid),
    async_request_handler(Request, State).
% A node store a key/value pair in its own values table.
% The node also saves the sender node in its routing table.
async_request_handler({store, Key, Value}, State) ->
    {RoutingTable, ValuesTable, K, T, Bucket_Size} = State,
    NewValuesTable = maps:put(Key, Value, ValuesTable),
    NewState = {RoutingTable, NewValuesTable, K, T, Bucket_Size},
    {noreply, NewState}
.

terminate(_Reason, _State) ->
    utils:debugPrint("Node ~p is terminating.~n", [my_address()]),
    ok
.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                            %%%
%%%     NODE AS A CLIENT       %%%
%%%                            %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% This function saves the node address (Pid) in the process 
% dictionary so that the process and all his subprocesses can
% use the same address
save_address(Address) ->
    put(my_address, Address).
% This function gets the process address
my_address() ->
    get(my_address).

% Verbose is used to decide if the debugPrint function
% should print the text or not 
set_verbose(Verbose) ->
    put(verbose, Verbose).

% This function is used for debugging purposess
% allowing to print the routing table in the shell
% sending a routing_table request to the given Pid
get_routing_table(NodePid) ->
    try
        gen_server:call(NodePid, {routing_table}, 50000)
    catch 
        Err -> utils:debugPrint("~p",[Err])
    end.

% This function is used to send synchronous requests to a node.
% NodeId is the node to which the request is sent.
send_request(NodePid, Request) when is_list(NodePid) ->
    send_request(list_to_pid(NodePid), Request);
send_request(NodePid, Request) when is_pid(NodePid) ->
    
    try
        gen_server:call(NodePid, {Request, my_address()}, 5000)
    catch _:Reason ->
        {error,Reason}
    end
.

% This function is used to send asynchronous requests to a node.
% NodeId is the node to which the request is sent.
send_async_request(NodePid, Request) ->
    gen_server:cast(NodePid, {Request, my_address()}).

% Finds the K closest nodes in the network to a given HashID.
% The function starts by querying the local routing table for potential candidates.
% It then iteratively contacts nodes to refine the list of closest nodes.
find_k_nearest_node(RoutingTable, HashID, Bucket_Size, K) ->
    % Retrieve the initial list of closest nodes from the routing table.
    NodeList = find_node(RoutingTable, Bucket_Size, K, HashID),
    % Begin the recursive search to refine the closest node list.
    find_k_nearest_node(HashID, Bucket_Size, K, NodeList, [])
.
% Base case: If there are no more nodes to contact, return the sorted list of the K 
% closest nodes.
find_k_nearest_node(HashID, _, K, [], ContactedNodes) -> 
    % Sort the contacted nodes by proximity to the HashID and return the top K nodes.
    SortedNodeList = utils:sort_node_list(ContactedNodes, HashID),
    lists:sublist(SortedNodeList, K);
% Recursive case: Process the next node in the list of candidates.
find_k_nearest_node(HashID, Bucket_Size, K, [{NodeHash, NodePid}|T], ContactedNodes) ->
    % Log the node being contacted for debugging purposes.
    % Send a request to the node to find its closest nodes to the HashID.
    case send_request(NodePid, {find_node, HashID}) of
        {ok, NodeList} ->
            % Filter the returned node list to exclude nodes already contacted or my_address.
            FilteredNodeList = lists:filter(
                fun(Node) -> 
                    {_, FilterPid} = Node,
                    not lists:member(Node, ContactedNodes) andalso
                    FilterPid /= pid_to_list(my_address())
                end, 
                NodeList
            ),
            % Combine the remaining nodes to process with the filtered nodes from the response.
            NewNodeList = lists:append(T, FilteredNodeList),
            % Add the current node to the list of contacted nodes.
            NewContactedNodes = lists:append(ContactedNodes, [{NodeHash, NodePid}]),
            % Recursively continue searching with the updated lists.
            Result = find_k_nearest_node(HashID, Bucket_Size, K, NewNodeList, NewContactedNodes);
        % If the request fails, skip the current node and continue with the rest.
        _ -> 
            Result = find_k_nearest_node(HashID, Bucket_Size, K, T, ContactedNodes)
    end,
    Result
.

% Finds the value associated with a given key in the network.
find_value(NodePid, Key) ->
    case send_request(NodePid, {find_value, Key}) of
        {ok, NodeList} when is_list(NodeList) -> 
            NodeList;
        {ok, Value} -> 
            Value
    end
.

% Pings a specific node (NodePid) to check its availability.
ping_node(NodePid) when is_list(NodePid) -> 
    ping_node(list_to_pid(NodePid));
ping_node(NodePid) when is_pid(NodePid) ->
    case send_request(NodePid, ping) of
        {pong,ok} ->
            {pong,ok};
        % If the node is unreachable, the function returns pang.
        {error, Reason} -> 
            {pang, Reason}
    end
.

% Client-side function to store a key/value pair in the K nodes closest
% to the hash_id of the pair.
store_value(Key, Value, RoutingTable, K, Bucket_Size) ->
    KeyHashId = utils:k_hash(Key, K),
    NodeList = find_k_nearest_node(RoutingTable, Key, KeyHashId, Bucket_Size, K),
    lists:foreach(
        fun({_NodeHashId, NodePid}) ->
            send_async_request(NodePid, {store, Key, Value})
        end,
        NodeList
    )
.


% Function to join the network. If no nodes exist, the actor becomes the bootstrap node.
% Otherwise, it contacts the existing bootstrap node.
join(RoutingTable, K, K_Bucket_Size) ->
    case whereis(bootstrap) of
        undefined -> 
            % No existing nodes, become the bootstrap node.
            register(bootstrap, my_address()),
            % Register this node as the bootstrap node in the global registry.
            % This way anyone knows the bootstrap and can join the network.
            utils:debugPrint("Node with pid ~p is the bootstrap node!~n", [my_address()]),
            {bootstrap, my_address()};
        BootstrapPid -> 
            % Contact the existing bootstrap node to join the network
            utils:print("~p is joining the network by contacting the existing bootstrap node (~p)~n", 
                [my_address(), BootstrapPid]),
            % Starting a new process to join the network.
            start_thread(
                fun() -> 
                    BootstrapHash = utils:k_hash(pid_to_list(BootstrapPid), K),
                    join_procedure_starter([{BootstrapHash, BootstrapPid}], RoutingTable, K, K_Bucket_Size)                    
                end
            )
    end 
.

% This function starts the join procedure.
% If at the end of the procedure there are still empty 
% branches the procedure is restarted after 2000 millis.
join_procedure_starter(NodesList, RoutingTable, K, K_Bucket_Size)->
    join_procedure(NodesList, RoutingTable, K, K_Bucket_Size, []),

    EmptyBranches = utils:empty_branches(RoutingTable, K),
    if EmptyBranches ->
        receive
        after 2000 ->
            utils:print("Restarting join procedure to fill missing branches ~p~n", [my_address()]),
            join_procedure_starter(NodesList, RoutingTable,K,K_Bucket_Size)
        end;
    true -> ok
    end
.

join_procedure([], _,_,_,_) ->
    ok;
join_procedure([{_,NodePid} | T], RoutingTable, K, K_Bucket_Size, ContactedNodes) ->

    save_node(NodePid),
    Tab2List = ets:tab2list(RoutingTable),
    FilledBrances = lists:foldl(
        fun({BranchID, List}, Acc) ->
            case List of
                [] -> Acc;
                _ -> [BranchID | Acc]
            end
        end,
        [],
        Tab2List
    ),
    case send_request(NodePid, {fill_my_routing_table, FilledBrances}) of
        {ok, {Branches, NearestNodes}} -> 
            lists:foreach(
                fun({_, NewNode}) ->
                    save_node(NewNode)
                end,
                Branches ++ NearestNodes
            ),
            % utils:debugPrint("Nearest List ~p to ~p~n", [NearestNodes, my_address()]),
            NewContactList = NearestNodes ++ T,

            FilteredNearestNodes = lists:foldl(fun(Element, Acc) ->
                {_,Pid} = Element,
                Condition = lists:member(Element, Acc) orelse lists:member(Pid, ContactedNodes),
                case Condition of
                    true -> Acc; 
                    false -> [Element | Acc]
                end
            end, [], NewContactList),
            
            SortedContactList = utils:sort_node_list(FilteredNearestNodes, my_hash_id(K)),
            K_NearestNodes = lists:sublist(SortedContactList, K_Bucket_Size),

            join_procedure(K_NearestNodes, RoutingTable, K, K_Bucket_Size, [NodePid|ContactedNodes]);
        Error -> 
            {error, Error}
    end.







