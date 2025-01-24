% -----------------------------------------------------------------------------
% Module: routing_table_filler
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-28
% Description: This module manages the behaviour of the thread that allows a node
%              to join the kademlia network.
% -----------------------------------------------------------------------------
%
%
-module(routing_table_filler).
-export([start/3, fill_routing_table/3, fill_routing_table/5, join_procedure/6, pick_bootstrap/0, nearest_bootstrap/1]).
-export([check_deletion_message/3, check_for_empty_branches/3, deleted_node/0]).

% This function starts the thread signaling the
% start and the end of the join procedure to the
% analytics_collector
start(K, RoutingTable, BucketSize) ->
    % Starting a new process to join the network.
    Pid = thread:start(
        fun() -> 
            EventId = analytics_collector:started_filling_routing_table(),
            ?MODULE:fill_routing_table(RoutingTable, K, BucketSize),
            analytics_collector:finished_filling_routing_table(EventId),

            ?MODULE:check_deletion_message(RoutingTable, K, BucketSize)
        end
    ),
    thread:save_named(routing_table_filler_pid, Pid),
    Pid
.

% This function is used to signal to
% the join thread that a node has been
% deleted from the routing table
deleted_node() ->
    case thread:get_named(routing_table_filler_pid) of
        undefined -> utils:print("Start a join thread before signaling deleted nodes");
        Pid -> Pid ! {deleted_node}
    end
. 

% This function checks if the node has been deleted from the network
% and if so it starts the check_for_empty_branches function
% to check if there are empty branches in the routing table.
check_deletion_message(RoutingTable, K, BucketSize) ->
    receive
        {deleted_node} ->
            ?MODULE:check_for_empty_branches(RoutingTable, K, BucketSize)

    after 1000 -> 
        ok         
    end,

    ?MODULE:check_deletion_message(RoutingTable, K, BucketSize)
.

% This function checks if there are empty branches in the routing table
% and if so it starts the join procedure again.
check_for_empty_branches(RoutingTable, K, BucketSize) ->
    EmptyBranches = utils:empty_branches(RoutingTable, K),
    if EmptyBranches -> 
        ?MODULE:fill_routing_table(RoutingTable, K, BucketSize, {ok, nearest_bootstrap}, true);
    true -> ok
    end
.

% This function is used to pick a random bootstrap node
% from those signaled to the analytics_collector
pick_bootstrap() ->
    BootstrapList = bootstrap_list_manager:get_bootstrap_list(),

    Length = length(BootstrapList),

    case length(BootstrapList) of
        0 -> 
            % Waiting for bootstrap nodes
            timer:sleep(2),
            ?MODULE:pick_bootstrap();
        Length ->                    
            Index = rand:uniform(Length),
            Bootstrap = lists:nth(Index, BootstrapList),
            Bootstrap
    end
.

% This function is used to get the nearest bootstrap node to this node
nearest_bootstrap(K) ->
    BootstrapList = bootstrap_list_manager:get_bootstrap_list(),
    %converting the list to a list of {hash, pid}
    BootstrapListFiltered =lists:foldl(
        fun(Pid, Acc) ->
            [{utils:k_hash(Pid, K), Pid} | Acc]
        end,
        [],
        BootstrapList
    ),

    case length(BootstrapListFiltered) of
        0 -> 
            % Waiting for bootstrap nodes
            timer:sleep(2),
            ?MODULE:nearest_bootstrap(K);
        _ ->                    
            [{_,First}|_] = utils:sort_node_list(BootstrapListFiltered, com:my_hash_id(K)),
            First
    end
.

% This function starts the join procedure.
% If at the end of the procedure there are still empty 
% branches the procedure is restarted after 2000 millis.
fill_routing_table(RoutingTable, K, K_Bucket_Size) ->
    ?MODULE:fill_routing_table(RoutingTable, K, K_Bucket_Size, {ok, nearest_bootstrap}, false).
fill_routing_table(RoutingTable, K, K_Bucket_Size, LastResult, JoinTimeSignaled)->
    thread:check_verbose(),
    case LastResult of
        {ok, random_bootstrap} ->
            BootstrapPid = ?MODULE:pick_bootstrap();
        {ok, nearest_bootstrap} ->
            BootstrapPid = ?MODULE:nearest_bootstrap(K)
    end,
    BootstrapHash = utils:k_hash(BootstrapPid, K),
        
    case JoinTimeSignaled of
        false->
            EventId = analytics_collector:started_join_procedure(),
            Result = ?MODULE:join_procedure([{BootstrapHash, BootstrapPid}], RoutingTable, K, K_Bucket_Size, [], []),
            analytics_collector:finished_join_procedure(EventId);
        true ->
            Result = ?MODULE:join_procedure([{BootstrapHash, BootstrapPid}], RoutingTable, K, K_Bucket_Size, [], [])
    end,


    EmptyBranches = utils:empty_branches(RoutingTable, K),
    if EmptyBranches ->
        ?MODULE:fill_routing_table(RoutingTable, K, K_Bucket_Size, Result, true);
    true -> 
        ok
    end
.

% The join procedure allows the node to join the network by contacting other nodes
% and exchanging routing data to fill its routing table.
join_procedure([], _,_,_,_,_) ->
    {ok, random_bootstrap};
join_procedure([{_,NodePid} | T], RoutingTable, K, K_Bucket_Size, ContactedNodes, LastFilledBranches) ->
    MyPid = com:my_address(),
    if NodePid /= MyPid ->
        % The first node is saved
        node:save_node(NodePid,RoutingTable,K,K_Bucket_Size),

        % Saving the branches that already have at least one element
        Tab2List = ets:tab2list(RoutingTable),
        FilledBranches = lists:foldl(
            fun({BranchID, List}, Acc) ->
                Size = length(List),
                if Size > 1 ->
                    [BranchID | Acc];
                true -> Acc
                end
            end,
            [],
            Tab2List
        ),
        FilledBranchesLen = length(FilledBranches),
        % If the node didn't have any filled branches or if it's the first node contacted
        % contact the new node.
        % We check the contact list length is different from 0 to make
        % sure small networks can converge.
        if FilledBranchesLen < K orelse length(ContactedNodes) == 0-> 
            % Sending request to the saved node, asking for new nodes.
            % This request will return the nodes in the opposite branches
            % relative to each consecutive shared bit in the head of the hash id.
            % The nearest nodes to the sender node are also returned. 
            % These will be the next nodes to contact because they share most of 
            % the branches with the sender.
            % The variable FilledBranches contains the branches that are already filled, 
            % allowing the receiver to ignore them and return only what's needed.
            case node:send_request(NodePid, {fill_my_routing_table, FilledBranches}, RoutingTable, K) of
                {ok, {Branches}} -> 
                    % saving all the new nodes
                    lists:foreach(
                        fun({_, NewNode}) ->
                            PidInRoutingTable = utils:pid_in_routing_table(RoutingTable, NewNode, K),
                            if not  PidInRoutingTable->
                                case node:ping(NewNode) of
                                    {pong, ok} ->
                                        node:save_node(NewNode,RoutingTable,K,K_Bucket_Size);
                                    _ -> ok
                                end;
                            true -> ok
                            end
                        end,
                        Branches
                    ),
                    utils:debug_print("Received ~p from ~p~n", [Branches, NodePid]),
                    NewContactedNodesList =  [NodePid|ContactedNodes],

                    RemovedContacted = utils:remove_contacted_nodes(T ++ Branches, NewContactedNodesList),
                    FilteredNewContactList = utils:remove_duplicates(RemovedContacted),
                    SortedNewContactList = utils:sort_node_list(FilteredNewContactList, com:my_hash_id(K)),
                
                    % Dont stop contacting known nodes until there 
                    % are no empty branches
                    EmptyBranches = utils:empty_branches(RoutingTable, K),
                    if EmptyBranches ->
                        LastFilledBranchesLen = length(LastFilledBranches),
                        if FilledBranchesLen > LastFilledBranchesLen ->
                            ?MODULE:join_procedure(SortedNewContactList, RoutingTable, K, K_Bucket_Size, NewContactedNodesList, FilledBranches);
                        true ->
                           {ok, nearest_bootstrap}
                        end;
                    true->
                        {ok, random_bootstrap}
                    end;
                Error -> 
                    utils:debug_print("Error occurred ~p~n", [Error]),
                    EmptyBranches = utils:empty_branches(RoutingTable, K),
                    if EmptyBranches ->
                        ?MODULE:join_procedure(T, RoutingTable, K, K_Bucket_Size, [NodePid|ContactedNodes], FilledBranches);
                    true->
                        {ok, random_bootstrap}
                    end
            end;
        true -> {ok, random_bootstrap}
        end;
    true ->  {ok, random_bootstrap}
    end
.


