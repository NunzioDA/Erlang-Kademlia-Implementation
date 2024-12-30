% -----------------------------------------------------------------------------
% Module: join_thread
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-28
% Description: This module manages the behaviour of the thread that allows a node
%              to join the kademlia network.
% -----------------------------------------------------------------------------
%
%
-module(join_thread).
-export([start/4, join_procedure_starter/3, join_procedure_starter/4, join_procedure/6, pick_bootstrap/0, nearest_bootstrap/1]).

% This function starts the thread signaling the
% start and the end of the join procedure to the
% analytics_collector
start(K, RoutingTable, BucketSize,SpareNodeManager) ->
    % Starting a new process to join the network.
    thread:start(
        fun() -> 
            put(spare_node_manager, SpareNodeManager),
            analytics_collector:started_join_procedure(com:my_address()),
            join_procedure_starter(RoutingTable, K, BucketSize),
            analytics_collector:finished_join_procedure(com:my_address())
        end
    )
.


% This function is used to pick a random bootstrap node
% from those signaled to the analytics_collector
pick_bootstrap() ->
    BootstrapList = analytics_collector:get_bootstrap_list(),
    BootstrapListFiltered =lists:filter(
        fun(Pid) ->
            Pid /= com:my_address()
        end,
        BootstrapList
    ),
    Length = length(BootstrapListFiltered),

    case length(BootstrapListFiltered) of
        0 -> -1;
        Length ->                    
            Index = rand:uniform(Length),
            Bootstrap = lists:nth(Index, BootstrapListFiltered),
            Bootstrap
    end.

nearest_bootstrap(K) ->
    BootstrapList = analytics_collector:get_bootstrap_list(),
    BootstrapListFiltered =lists:foldl(
        fun(Pid, Acc) ->
            case Pid == com:my_address() of 
                true -> Acc;
                false -> [{utils:k_hash(Pid, K), Pid} | Acc]
            end
        end,
        [],
        BootstrapList
    ),
    [First|_] = utils:sort_node_list(BootstrapListFiltered, com:my_hash_id(K)),
    First.

% This function starts the join procedure.
% If at the end of the procedure there are still empty 
% branches the procedure is restarted after 2000 millis.
join_procedure_starter(RoutingTable, K, K_Bucket_Size) ->
    ?MODULE:join_procedure_starter(RoutingTable, K, K_Bucket_Size, {ok, nearest_bootstrap}).
join_procedure_starter(RoutingTable, K, K_Bucket_Size, LastResult)->
    thread:check_verbose(),
    case LastResult of
        {ok, random_bootstrap} ->
            BootstrapPid = ?MODULE:pick_bootstrap();
        {ok, nearest_bootstrap} ->
            BootstrapPid = ?MODULE:nearest_bootstrap(K)
    end,
    if(is_pid(BootstrapPid)) ->
        BootstrapHash = utils:k_hash(BootstrapPid, K),
        Result = ?MODULE:join_procedure([{BootstrapHash, BootstrapPid}], RoutingTable, K, K_Bucket_Size, [], []),

        % Restart join procedure if there are empty branches
        EmptyBranches = utils:empty_branches(RoutingTable, K),
        if EmptyBranches ->
            ?MODULE:join_procedure_starter(RoutingTable, K, K_Bucket_Size, Result);
        true -> ok
        end;
    true -> 
        ?MODULE:join_procedure_starter(RoutingTable, K, K_Bucket_Size)
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
                case List of
                    [] -> Acc;
                    _ -> [BranchID | Acc]
                end
            end,
            [],
            Tab2List
        ),
        FilledBranchesLen = length(FilledBranches),
        if FilledBranchesLen < K ->
            % Sending request to the saved node, asking for new nodes.
            % This request will return the nodes in the opposite branches
            % relative to each consecutive shared bit in the head of the hash id.
            % The nearest nodes to the sender node are also returned. 
            % These will be the next nodes to contact because they share most of 
            % the branches with the sender.
            % The variable FilledBranches contains the branches that are already filled, 
            % allowing the receiver to ignore them and return only what's needed.
            case node:send_request(NodePid, {fill_my_routing_table, FilledBranches}) of
                {ok, {Branches}} -> 
                    % saving all the new nodes
                    lists:foreach(
                        fun({_, NewNode}) ->
                            node:save_node(NewNode,RoutingTable,K,K_Bucket_Size)
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
                    %%% HalfBucket = K_Bucket_Size div 2,
                    %%% BranchesWithLessThenHalf = utils:branches_with_less_then(RoutingTable, HalfBucket, K),
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


