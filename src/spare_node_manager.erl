% -----------------------------------------------------------------------------
% Module: spare_node_manager
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-26
% Description: This module manages the spare nodes when the routing table 
%              is full pinging the oldest node in the branch and changing
%              it if the communication fails.
% -----------------------------------------------------------------------------

-module(spare_node_manager).
-behaviour(gen_server).

-export([start/2, start_link/4, init/1, handle_call/3, handle_cast/2, delegate/1, append_node/5, handle_info/2]).

% Starting the spare node manager linking it to the parent
start(RoutingTable, K)->
    ParentAddress = com:my_address(),
    Verbose = utils:verbose(),
    Pid = ?MODULE:start_link(ParentAddress,Verbose, RoutingTable, K),
    thread:save_thread(Pid),
    thread:save_named(spare_node_manager, Pid),
    Pid.

% starting gen server
start_link(ParentAddress, Verbose, RoutingTable, K) ->
    {ok, Pid} = gen_server:start_link(?MODULE, [ParentAddress, Verbose, RoutingTable, K], []),
    Pid.

% delegate the node to the spare_node_manager
delegate(Pid)->
    ServerPid = thread:get_named(spare_node_manager),

    if ServerPid /= undefined ->
        gen_server:cast(ServerPid, {check, Pid});
    true ->
        utils:print("Start a spare node manager before delegating pids")
    end.

% Initializing gen_server
init([ParentAddress, Verbose, RoutingTable, K]) ->
    utils:set_verbose(Verbose),
    com:save_address(ParentAddress),
    LastUpdatedBranch = -1,
    {ok, {RoutingTable, K, LastUpdatedBranch}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

% This function is used to append a node to al 
append_node(RoutingTable, Tail, NodeHashId, NodePid, BranchID) ->
    UpdatedNodeList = Tail ++ [{NodeHashId, NodePid}], 
    ets:insert(RoutingTable, {BranchID, UpdatedNodeList}).

% Handling the spare node
handle_cast({check, NodePid}, State) ->
    {RoutingTable, K,LastUpdatedBranch} = State,
    NodeHashId = utils:k_hash(NodePid, K),
    BranchID = utils:get_subtree_index(NodeHashId, com:my_hash_id(K)),

    % Only start the ping and change procedure
    % if the last updated branch is different from the
    % current node branch.
    % This is used to avoid endless pinging sequence.
    if LastUpdatedBranch /= BranchID ->
        NewLastUpdatedBranch = BranchID,

        [{_,NodeList}] = ets:lookup(RoutingTable, BranchID),

        % Extract the least recently seen node in the list.
        [{LeastRecentNodeHashId, LeastRecentNodePid} | Tail] = NodeList,
        % Check if the least recent node is still responsive.
        case node:ping(LeastRecentNodePid) of 
            % If the least recent node is responsive, discard the new node with
            % a probability of 4/5 and add the new node with a probability
            % of 1/5.
            % This is used to increase the probability that a new node
            % is known by some node in the network.
            {pong, ok} -> 
                RandomNumber = rand:uniform(5),
                if RandomNumber == 5 ->
                    ?MODULE:append_node(RoutingTable, Tail, NodeHashId, NodePid, BranchID);
                true ->
                    ?MODULE:append_node(RoutingTable, Tail, LeastRecentNodeHashId, LeastRecentNodePid, BranchID)
                end;
            % If the least recent node is not responsive, discard it and add the new node.
            {pang, _} -> 
                ?MODULE:append_node(RoutingTable, Tail, NodeHashId, NodePid, BranchID)
        end;
    true -> 
        NewLastUpdatedBranch = LastUpdatedBranch
    end,
    {noreply, {RoutingTable,K,NewLastUpdatedBranch}}.

% Handling thread verbosity messages
handle_info({verbose, Verbose}, State)->
    utils:set_verbose(Verbose),
    {noreply, State}.