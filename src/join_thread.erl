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
-export([start/3, join_procedure_starter/3, join_procedure/5, pick_bootstrap/0]).

% This function starts the thread signaling the
% start and the end of the join procedure to the
% analytics_collector
start(K, RoutingTable, BucketSize) ->
    % Starting a new process to join the network.
    thread:start(
        fun() -> 
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
    Length = length(BootstrapList),                    
    Index = rand:uniform(Length),
    Bootstrap = lists:nth(Index, BootstrapList),
    Bootstrap.

% This function starts the join procedure.
% If at the end of the procedure there are still empty 
% branches the procedure is restarted after 2000 millis.
join_procedure_starter(RoutingTable, K, K_Bucket_Size)->
    thread:check_verbose(),
    utils:debug_print("Starting join procedure to fill missing branches ~p~n", [com:my_address()]),
    
    BootstrapPid = ?MODULE:pick_bootstrap(),
    BootstrapHash = utils:k_hash(BootstrapPid, K),
    ?MODULE:join_procedure([{BootstrapHash, BootstrapPid}], RoutingTable, K, K_Bucket_Size, []),

    % Restart join procedure if there are empty branches
    EmptyBranches = utils:empty_branches(RoutingTable, K),
    if EmptyBranches ->
        timer:sleep(2000),
        ?MODULE:join_procedure_starter(RoutingTable, K, K_Bucket_Size);
    true -> ok
    end
.

% The join procedure allows the node to join the network by contacting other nodes
% and exchanging routing data to fill its routing table.
join_procedure([], _,_,_,_) ->
    ok;
join_procedure([{_,NodePid} | T], RoutingTable, K, K_Bucket_Size, ContactedNodes) ->
    MyPid = com:my_address(),
    if NodePid /= MyPid ->
        % The first node is saved
        node:save_node(NodePid),

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
        if FilledBranchesLen < K + 1 ->
            % Sending request to the saved node, asking for new nodes.
            % This request will return the nodes in the opposite branches
            % relative to each consecutive shared bit in the head of the hash id.
            % The nearest nodes to the sender node are also returned. 
            % These will be the next nodes to contact because they share most of 
            % the branches with the sender.
            % The variable FilledBranches contains the branches that are already filled, 
            % allowing the receiver to ignore them and return only what's needed.
            utils:debug_print("Contacting node ~p~n", [NodePid]),
            case node:send_request(NodePid, {fill_my_routing_table, FilledBranches}) of
                {ok, {Branches}} -> 
                    utils:debug_print("Done node ~p~n", [NodePid]),
                    % saving all the new nodes
                    lists:foreach(
                        fun({_, NewNode}) ->
                            node:save_node(NewNode)
                        end,
                        Branches
                    ),
                    utils:debug_print("Nearest List ~p to ~p~n", [Branches, com:my_address()]),
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
                        ?MODULE:join_procedure(SortedNewContactList, RoutingTable, K, K_Bucket_Size, NewContactedNodesList);
                    true->
                        ok
                    end;
                Error -> 
                    utils:debug_print("Error occurred ~p~n", [Error]),
                    ?MODULE:join_procedure(T, RoutingTable, K, K_Bucket_Size, [NodePid|ContactedNodes])
            end;
        true -> ok
        end;
    true -> ok
    end
.


