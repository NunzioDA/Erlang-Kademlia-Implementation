% -----------------------------------------------------------------------------
% Module: node
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-20
% Description: This module manages the node behaviour.
% -----------------------------------------------------------------------------

-module(node).
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, terminate/2, kill/1, handle_info/2]).
-export([start/3, start/4, ping/1, distribute_value/5, send_request/4, lookup/3, shell_find_nearest_nodes/2]).
-export([distribute/3, lookup/2, get_routing_table/1, talk/1, shut/1, start_server/4]).
-export([save_node/4, branch_lookup/2, find_node/7, find_node/4, get_value/3, request_handler/3, delete_node/3]).
-export([async_request_handler/2, find_k_nearest_node/6, lookup_for_value/5, find_k_nearest_node/4, send_ping/2]).

% Starts a new node in the Kademlia network.
% K -> Number of bits to represent a node ID.
% T -> Time interval for republishing data.
% Returns the process identifier (PID) of the newly created node.
start(K, T, InitAsBootstrap) ->
    ?MODULE:start(K, T, InitAsBootstrap, false).

start(K, T, InitAsBootstrap, Verbose) ->
    Pid = ?MODULE:start_server(K, T, InitAsBootstrap, Verbose),
    Pid.

% Starts the node process.
% gen_server:start/3 calls init/1, who takes in input [K, T].
start_server(K, T, InitAsBootstrap, Verbose) ->
    {ok, Pid} = gen_server:start(?MODULE, [K, T, InitAsBootstrap, Verbose], []),
    Pid.

% Initializes the state of the node when it is created.
% Creates one ETS table and a map:
% - RoutingTable: Used to store the routing information of the node.
% - ValuesMap: Used to store key-value pairs managed by the node.
init([K, T, InitAsBootstrap, Verbose]) ->
    % Trapping exit so we can catch exit messages
    process_flag(trap_exit, true),
    
    utils:set_verbose(Verbose),
    % Generate a unique integer to create distinct ETS table names for each node.
    UniqueInteger = integer_to_list(erlang:unique_integer([positive])),    
    % Create unique table name for routing by appending the unique integer.
    RoutingName = list_to_atom("routing_table" ++ UniqueInteger),
    ValuesMapName = list_to_atom("values_table" ++ UniqueInteger),
    % Initialize ETS table with the specified properties.
    RoutingTable = ets:new(RoutingName, [set, public]),
    % Initialize ValuesTable as an empty map.
    ValuesTable = ets:new(ValuesMapName, [set, public]),
    % Define the bucket size for routing table entries.
    Bucket_Size = 20,

    spare_node_manager:start(RoutingTable, K),
    republisher:start(RoutingTable, K, T, Bucket_Size),
    analytics_collector:enroll_node(),

    if InitAsBootstrap ->
        analytics_collector:enroll_bootstrap();
    true -> ok
    end,
    
    join_thread:start(K,RoutingTable,Bucket_Size),

    % Return the initialized state, containing ETS tables and configuration parameters.
    {ok, {RoutingTable, ValuesTable, K, T, Bucket_Size}}.

%-------------------------------------------------------
% SHELL COMMANDS
%
% The following functions can be called from the shell
% to tell a specific node what to do.
% All the functions are used for debugging purposes.
%------------------------------------------------------
%
% This function is used for debugging purposess
% allowing to print the routing table in the shell
% sending a routing_table request to the given Pid
get_routing_table(NodePid) when is_pid(NodePid)->
    try
        gen_server:call(NodePid, {routing_table}, 120000)
    catch 
        Err -> utils:debug_print("~p",[Err])
    end.
% This function is used to make the node start the store
% procedure, contacting the nearest node to the value
distribute(NodePid, Key, Value) when is_pid(NodePid)->
    com:send_async_request(NodePid, {distribute_value, Key, Value}).

% This function is used to make the node start the lookup
% procedure, contacting the nearest node to the value
lookup(NodePid, Key) when is_pid(NodePid) ->
    ?MODULE:lookup(NodePid, Key, true).
lookup(NodePid, Key, Verbose) when is_pid(NodePid) ->
    com:send_request(NodePid, {shell_lookup, Key, Verbose}).

% This function is used to change the node verbosity to true
talk(NodePid) when is_pid(NodePid)->
    com:send_async_request(NodePid, {talk}).

% This function is used to change the node verbosity to false
shut(NodePid) when is_pid(NodePid) ->
    com:send_async_request(NodePid, {shut}).

% This function is used from the shell
% to start a procedure to find the K nearest nodes
% to a given hash id
shell_find_nearest_nodes(NodePid, HashId) ->
    com:send_request(NodePid, {shell_find_nearest_nodes, HashId}).

% This function is used from the shell 
% to tell a node to send a ping to another node
send_ping(NodePid,ToNodePid) when is_pid(NodePid) ->
    com:send_request(NodePid, {send_ping, ToNodePid}).

% This command is used to kill a process
kill(Pid) when is_pid(Pid) ->
    % Unlinking so the parent is not killed
    unlink(Pid),
    exit(Pid, kill).

% Pings a specific node (NodePid) to check its availability.
ping(NodePid) when is_pid(NodePid) ->
    case com:send_request(NodePid, ping) of
        {pong,ok} ->
            {pong,ok};
        % If the node is unreachable, the function returns pang.
        {error, Reason} -> 
            {pang, Reason}
    end.

% ----------------------------------------------------------------------------
%   ROUTING TABLE MANAGEMENT 
% ----------------------------------------------------------------------------

% NodePid: The process identifier of the node to be saved. It is used to contact the node.
% RoutingTable: the table where store the information.
% K: The number of bits used for the node's hash_id representation.
save_node(NodePid, RoutingTable, K, K_Bucket_Size) when is_pid(NodePid) ->
    MyAddress = com:my_address(),
    ShellPid = whereis(shellPid),
    if(NodePid /= ShellPid andalso NodePid /= MyAddress) ->
        NodeHashId = utils:k_hash(NodePid, K),
        % Determine the branch ID in the routing table corresponding to the hash ID.
        BranchID = utils:get_subtree_index(NodeHashId, com:my_hash_id(K)),

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
                case lists:member({NodeHashId,NodePid}, NodeList) of
                    true ->
                        % If the node is already in the list, move it to the end
                        RemovedNodeList = lists:filter(
                            fun({_, ElementPid}) -> 
                                ElementPid /= NodePid 
                            end, 
                            NodeList
                        ),
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
                                % Delegating spare node to the spare_node_manager
                                spare_node_manager:delegate(NodePid)
                        end
                end
        end;
    true -> ok
    end.

% This function delete a node from the routing table
delete_node(NodePid, RoutingTable, K) when is_pid(NodePid)->
    NodeHashId = utils:k_hash(NodePid, K),
    BranchID = utils:get_subtree_index(NodeHashId, com:my_hash_id(K)),
    case ets:lookup(RoutingTable, BranchID) of
        [{BranchID, NodeList}] ->
            NewNodeList = lists:filter(fun({_, Pid}) -> Pid =/= NodePid end, NodeList),

            LenBefore = length(NodeList),
            LenAfter = length(NewNodeList),
            if LenBefore /= LenAfter ->
                ets:insert(RoutingTable, {BranchID, NewNodeList}),
                join_thread:deleted_node();
            true -> ok
            end;

        [] -> ok
    end.

% This function is used to lookup for the nodes list in a branch.
branch_lookup(RoutingTable, BranchId) ->
    case ets:lookup(RoutingTable, BranchId) of
        % Return a list if BranchId is found.
        [{BranchId, NodeList}] -> NodeList;
        % Return an empty list if BranchId is not found.
        [] -> [] 
    end.

% This function is used to lookup for the K closest nodes starting from a branch in local.
% After checking the current branch, the function checks the branches on the left and on the right
% till it finds K nodes or the end of the routing table.
% HashId is the target hash ID for which we are looking for the closest nodes.
% The function returns a list containing the K closest nodes to HashId.
find_node(RoutingTable, K_Bucket_Size, K, HashId) ->
    BranchID = utils:get_subtree_index(HashId, com:my_hash_id(K)),
    % Start the recursive lookup from the initial state: 0 nodes found, initial index I = 0.
    ?MODULE:find_node(RoutingTable, 0, K_Bucket_Size, BranchID, K, HashId, 0).
% Main function that recursively searches for K closest nodes. NodesCount is the number
% of nodes collected so far. BranchID is the starting index for lookup. I is the current
% step or offset in the lookup process.
find_node(RoutingTable, NodesCount, K_Bucket_Size, BranchID, K, HashId, I) 
    when BranchID + I =< K; BranchID - I >= 0 , NodesCount < K_Bucket_Size ->
        % Look up nodes in the branch on the right (BranchID + I).
        % I = 0, so first we look within the starting branch.
        if 
            BranchID + I =< K ->
                NodesList = ?MODULE:branch_lookup(RoutingTable, BranchID + I);
            true -> 
                NodesList = []
        end,
        % Get the size of NodesList.
        Len = length(NodesList),
        % Look up nodes in the branch on the left (BranchID - I).
        if 
            BranchID - I >= 0, Len < K_Bucket_Size, I > 0 ->
                OtherNodes = ?MODULE:branch_lookup(RoutingTable, BranchID - I);        
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
                OtherNodes2 = ?MODULE:find_node(RoutingTable, Len2, K_Bucket_Size, BranchID, K, HashId, I + 1)
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
        [].

get_value(Key, K, ValuesTable) ->
    KeyHash = utils:k_hash(Key, K),
    case ets:lookup(ValuesTable, KeyHash) of
        [{KeyHash, ValuesMap}] ->
            case maps:is_key(Key, ValuesMap) of
                true ->
                    Value = maps:get(Key, ValuesMap),
                    {ok, Key, Value};
                false ->
                    {no_value, empty}
            end;
        [] ->
            {no_value, empty}
    end.

%-----------------------------------------------------------------------------------
% SYNCHRONOUS REQUESTS MANAGEMENT 
%-----------------------------------------------------------------------------------
% 
% This request is used to print the routing table
% of a specific node.
% This is used in the shell to debugging purposes.
handle_call({routing_table}, _From, State) ->
    {RoutingTable, _, _, _, _} = State,
    % Return = utils:print_routing_table(RoutingTable, com:my_hash_id(K)),
    {reply, {ok, ets:tab2list(RoutingTable)}, State};
% Handling synchronous requests to the node.
% The sending node of the request is stored in the recipient's routing table.
handle_call({Request, SenderPid}, _, State) ->  
    % Save the sender node in the routing table.
    utils:debug_print("Handling ~p ~p~n", [Request, SenderPid]),
    {RoutingTable, _, K, _, BucketSize} = State,
    ?MODULE:save_node(SenderPid,RoutingTable,K,BucketSize),
    ?MODULE:request_handler(Request, SenderPid, State).

% Handles a request to find the closest nodes to a given HashID.
% HashID: The identifier of the target node.
% State: The current state of the node, including the routing table.
request_handler({find_node, HashID}, _From, State) ->
    {RoutingTable, _, K, _, Bucket_Size} = State,
    % Look up the closest K nodes within the routing table.
    NodeList = ?MODULE:find_node(RoutingTable, Bucket_Size, K, HashID),
    % Reply to the caller with the list of closest nodes and the current state.
    {reply, {ok, NodeList}, State};
request_handler({find_value, Key}, _From, State) ->
    {RoutingTable, ValuesTable, K, _, Bucket_Size} = State,

    case ?MODULE:get_value(Key, K, ValuesTable) of 
        {ok, Key, Value} -> 
            % If the key is found in the local values table, return the value.
            {reply, {ok, Key, Value}, State};
        {no_value, empty} ->
            % Compute the hash ID of the key to search for.
            KeyHashId = utils:k_hash(Key, K),
            % If the key is not found, look up the closest K nodes to the key's hash ID.
            NodeList = ?MODULE:find_node(RoutingTable, Bucket_Size, K, KeyHashId),
            % Reply with the list of closest nodes to the key.
            {reply, {nodes_list, NodeList}, State}
    end;
% This request is used during the join operation to fill the routing table of the new node.
request_handler({fill_my_routing_table, FilledIndexes}, ClientPid, State) ->
    {RoutingTable, _, K, _, Bucket_Size} = State,
    % First the server finds all the branches that it shares with the client
    % making the filling procedue more efficient.
    ClientHash = utils:k_hash(ClientPid, K),
    SubTreeIndex = utils:get_subtree_index(com:my_hash_id(K), ClientHash),

    AllBranches = lists:seq(1, SubTreeIndex - 1),
    % The server avoids to lookup for the branches that the client have already filled.
    BranchesToLookup = lists:filter(
        fun(X) -> 
            not lists:member(X, FilledIndexes)        
        end, 
        AllBranches
    ),

    % Here the node will get all the nodes
    % it knows for the buckets that are shared
    % with the client.
    % 
    % If the server has the hash 1001 and the client
    % has the hash 1010 they share the first two bits.
    % Their routing table will share the buckets containing
    % the nodes starting with 0--- and all the nodes starting
    % with 10--.
    % So those buckets will be passed entirely making the
    % join procedure more efficent.
    Branches = lists:foldl(
        fun(Branch, NodeList) ->
            BranchContent = ?MODULE:branch_lookup(RoutingTable, Branch),
            NodeList ++ BranchContent
        end,
        [],
        BranchesToLookup
    ),

    % If the nodes dont have the same hash take at
    % most Bucket_Size div 2 nodes from each of the 
    % remaining buckets giving the client some 
    % node to contact
    if SubTreeIndex =< K ->
        OtherBranchesToLookUp = lists:seq(SubTreeIndex, K),
        OtherBranches = lists:foldl(
            fun(Branch, NodeList) ->
                BranchContent = ?MODULE:branch_lookup(RoutingTable, Branch),
                BranchLen = length(BranchContent),
                if(BranchLen > (Bucket_Size div 2)) -> 
                    HalfBranch = lists:sublist(BranchContent, 1, Bucket_Size div 2);
                true ->
                    HalfBranch = BranchContent
                end,
                NodeList ++ HalfBranch
            end,
            [],
            OtherBranchesToLookUp
        );
    true -> OtherBranches = []
    end,

    % The server returns the nearest nodes to the client that are next to be requested.
    NearestNodes = ?MODULE:find_node(RoutingTable, 2, K, ClientHash),
    Response = {ok, {Branches ++ OtherBranches ++ NearestNodes}},
    {reply, Response, State};

% Handles the ping message sent to a node.
request_handler(ping, _, State) ->
    % Reply with pong to indicate that the node is alive and reachable.
    {reply, {pong, ok}, State};
% This request is used from the shell
% to tell a node to send a ping to another node
request_handler({send_ping, ToNodePid}, _, State) ->
    Result = ?MODULE:ping(ToNodePid),
    {reply, Result, State};
% This function is used to find a value in the network 
% from the shell
request_handler({shell_lookup, Key, Verbose}, _, State) ->
    {RoutingTable,_,K,_,_} = State,
    thread:start(
        fun() ->
            EventId = analytics_collector:started_lookup(),
            case ?MODULE:lookup_for_value(Key, K, [{com:my_hash_id(K), com:my_address()}], [], RoutingTable) of
                {value_not_found, empty} ->
                    if(Verbose) ->
                        utils:print("[~p] Value ~p not found~n", [com:my_address(), Key]);
                    true-> ok
                    end;
                {ok, _, Value} ->
                    if(Verbose) ->
                        utils:print("[~p] Value found: ~p => ~p~n", [com:my_address(), Key, Value]);
                    true-> ok
                    end
            end,
            analytics_collector:finished_lookup(EventId)
        end   
    ),
    {reply, ok, State};
request_handler({shell_find_nearest_nodes, HashId},_,State) ->
    {RoutingTable, _, K, _, BucketSize} = State,
    Result = ?MODULE:find_k_nearest_node(RoutingTable, HashId, BucketSize, K),
    {reply, Result, State};
% Handles any unrecognized request by replying with an error.
request_handler(_, _, State) ->
    {reply, not_handled_request, State}.

% ---------------------------------------------------------------- 
% ASYNCHRONOUS REQUESTS MANAGEMENT
% ---------------------------------------------------------------- 
%
handle_cast({Request, SenderPid}, State) when is_tuple(Request) ->
    utils:debug_print("Handling ~p", [Request]),
    {RoutingTable, _, K, _, BucketSize} = State,
    ?MODULE:save_node(SenderPid,RoutingTable,K,BucketSize),
    ?MODULE:async_request_handler(Request, State).

% A node store a key/value pair in its own values table.
% The node also saves the sender node in its routing table.
async_request_handler({store, Key, Value}, State) ->
    {_, ValuesTable, K, _, _} = State,
    KeyHash = utils:k_hash(Key, K),
    case ets:lookup(ValuesTable, KeyHash) of
        [] -> 
            ets:insert(ValuesTable, {KeyHash, #{Key => Value}});
        [{_,ValuesMap}] ->
            KeyIsKey = maps:is_key(Key, ValuesMap),
            if not KeyIsKey ->
                NewValuesMap = maps:put(Key, Value, ValuesMap),
                ets:insert(ValuesTable, {KeyHash, NewValuesMap});
            true ->
                ok
            end 
    end,
    analytics_collector:stored_value(Key),
    {noreply, State};
async_request_handler({distribute_value, Key, Value}, State) ->
    republisher:add_pair(Key, Value),
    {noreply, State};
async_request_handler({talk},State) ->
    utils:set_verbose(true),
    thread:set_verbose(true),
    {noreply, State};
async_request_handler({shut},State) ->
    utils:set_verbose(false),
    thread:set_verbose(false),
    {noreply, State}.

terminate(Reason, _State) ->
    utils:debug_print("Node ~p is terminating for reason: ~p.~n", [com:my_address(), Reason]),
    ok.

handle_info({'EXIT', FromPid, _}, State) ->
    {RoutingTable, _, K, T, Bucket_Size} = State,
    JoinThread = get(join_thread_pid),
    RepublisherThread = get(republisher_pid),
    SpareNodeManagerThread = get(spare_node_manager),

    if FromPid == JoinThread ->
        % Restarting join thread
        join_thread:start(K,RoutingTable,Bucket_Size);
    FromPid == RepublisherThread ->
        % Restarting republisher thread
        republisher:start(RoutingTable, K, T, Bucket_Size);
    FromPid == SpareNodeManagerThread ->
        % Restarting spare node manager thread
        spare_node_manager:start(RoutingTable, K);
    true -> ok
    end, 
    thread:check_threads_status(),
    {noreply, State};
handle_info(_,State) ->
    {noreply, State}.    

%----------------------------------------------
%  NODE AS A CLIENT
%----------------------------------------------
%
send_request(Pid,Request,RoutingTable, K) -> 
    case com:send_request(Pid, Request) of
        {error, Reason} ->
            ?MODULE:delete_node(Pid, RoutingTable, K),
            {error,Reason};
        Response -> Response
    end.
% Finds the K closest nodes in the network to a given HashID.
% The function starts by querying the local routing table for potential candidates.
% It then recoursively contacts nodes to refine the list of closest nodes.
find_k_nearest_node(RoutingTable, HashID, BucketSize, K) ->
    % Retrieve the initial list of closest nodes from the routing table.
    NodeList = ?MODULE:find_node(RoutingTable, BucketSize, K, HashID),
    % Begin the recursive search to refine the closest node list.
    ?MODULE:find_k_nearest_node(RoutingTable, HashID, BucketSize, K, NodeList, []).

% Base case: If there are no more nodes to contact, return the sorted list of the K 
% closest nodes.
find_k_nearest_node(_, HashID, BucketSize, _, [], ContactedNodes) -> 
    % Sort the contacted nodes by proximity to the HashID and return the top K nodes.
    NoDuplicate = utils:remove_duplicates(ContactedNodes),
    SortedNodeList = utils:sort_node_list(NoDuplicate, HashID),
    lists:sublist(SortedNodeList, BucketSize);
% Recursive case: Process the next node in the list of candidates.
find_k_nearest_node(RoutingTable, HashID, BucketSize, K, [{NodeHash, NodePid}|T], ContactedNodes) ->
    % Log the node being contacted for debugging purposes.
    % Send a request to the node to find its closest nodes to the HashID.
    case ?MODULE:send_request(NodePid, {find_node, HashID},RoutingTable,K) of
        {ok, NodeList} ->
            % Filter the returned node list to exclude nodes already contacted or com:my_address.
            FilteredNodeList = lists:filter(
                fun(Node) -> 
                    {_, FilterPid} = Node,
                    not lists:member(Node, ContactedNodes) andalso
                    FilterPid /= com:my_address()
                end, 
                NodeList
            ),
            % Combine the remaining nodes to process with the filtered nodes from the response.
            NewNodeList = lists:append(T, FilteredNodeList),
            NoDuplicate = utils:remove_duplicates(NewNodeList),
            SortedNodeList = utils:sort_node_list(NoDuplicate, HashID),
            K_NodeList = lists:sublist(SortedNodeList, BucketSize),
            % Add the current node to the list of contacted nodes.
            NewContactedNodes = lists:append(ContactedNodes, [{NodeHash, NodePid}]),
            % Recursively continue searching with the updated lists.
            Result = ?MODULE:find_k_nearest_node(RoutingTable, HashID, BucketSize, K, K_NodeList, NewContactedNodes);
        % If the request fails, skip the current node and continue with the rest.
        _ -> 
            Result = ?MODULE:find_k_nearest_node(RoutingTable, HashID, BucketSize, K, T, ContactedNodes)
    end,
    Result.

% Client-side function to store a key/value pair in the K nodes closest
% to the hash_id of the pair.
distribute_value(Key, Value, RoutingTable, K, Bucket_Size) ->
    Event = analytics_collector:started_distribute(),
    KeyHashId = utils:k_hash(Key, K),
    NodeList = ?MODULE:find_k_nearest_node(RoutingTable, KeyHashId, Bucket_Size, K),
    lists:foreach(
        fun({_NodeHashId, NodePid}) ->
            com:send_async_request(NodePid, {store, Key, Value})
        end,
        NodeList
    ),
    analytics_collector:finished_distribue(Event).

% Finds the value associated with a given key in the network
% by sending find_value requests to node that are every time closer to
% the given value
lookup_for_value(_, _, [], _, _) ->
    {value_not_found, empty};
lookup_for_value(Key, K, [{_, Pid} | T], ContactedNodes, RoutingTable) ->
    case ?MODULE:send_request(Pid, {find_value, Key}, RoutingTable, K) of
        {nodes_list, NodeList} ->
            NextNodesList = NodeList ++ T, 
            NewContactedNodes = [Pid | ContactedNodes],
            NewNodeList = utils:remove_contacted_nodes(NextNodesList, NewContactedNodes),
            SortedNodeList = utils:sort_node_list(NewNodeList, utils:k_hash(Key,K)),

            ?MODULE:lookup_for_value(Key, K, SortedNodeList, NewContactedNodes, RoutingTable);
        {ok, ValueKey, Value} ->
            {ok, ValueKey, Value};
        _ -> ?MODULE:lookup_for_value(Key,K, T, [Pid | ContactedNodes],RoutingTable)
    end.





