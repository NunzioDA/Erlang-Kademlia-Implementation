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

-export([start/2, start_link/4, init/1, handle_call/3, handle_cast/2, delegate/1, last_updated_branch/0]).

% Starting the spare node manager linking it to the parent
start(RoutingTable, K)->
    ParentAddress = com:my_address(),
    Verbose = utils:verbose(),
    Pid = ?MODULE:start_link(ParentAddress,Verbose, RoutingTable, K),
    put(spare_node_manager, Pid),
    Pid.

% starting gen server
start_link(ParentAddress, Verbose, RoutingTable, K) ->
    {ok, Pid} = gen_server:start_link(?MODULE, [ParentAddress, Verbose, RoutingTable, K], []),
    Pid.

% delegate the node to the spare_node_manager
delegate(Pid)->
    ServerPid = get(spare_node_manager),
    gen_server:cast(ServerPid, {check, Pid}).

% Initializing gen_server
init([ParentAddress, Verbose, RoutingTable, K]) ->
    utils:set_verbose(Verbose),
    com:save_address(ParentAddress),
    {ok, {RoutingTable, K}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

% Check what is the last updated branch
last_updated_branch()->
    case get(last_updated_branch) of
        undefined -> -1;
        BranchID -> BranchID
    end.

% Handling the spare node
handle_cast({check, NodePid}, State) ->
    {RoutingTable, K} = State,
    NodeHashId = utils:k_hash(NodePid, K),
    BranchID = utils:get_subtree_index(NodeHashId, com:my_hash_id(K)),
    LastUpdatedBranch = ?MODULE:last_updated_branch(),

    % Only start the ping and change procedure
    % if the last updated branch is different from the
    % current node branch.
    % This is used to avoid endless pinging sequence.
    if LastUpdatedBranch /= BranchID ->
        put(last_updated_branch, BranchID),

        [{_,NodeList}] = ets:lookup(RoutingTable, BranchID),

        % Extract the last seen node in the list.
        [{LastSeenNodeHashId, LastSeenNodePid} | Tail] = NodeList,
        % Check if the last node is still responsive.
        case node:ping_node(LastSeenNodePid) of 
            % If the last node is responsive, discard the new node.
            {pong, ok} -> 
                UpdatedNodeList = Tail ++ [{LastSeenNodeHashId, LastSeenNodePid}], 
                ets:insert(RoutingTable, {BranchID, UpdatedNodeList});
            % If the last node is not responsive, discard it and add the new node.
            {pang, _} -> 
                UpdatedNodeList = Tail ++ [{NodeHashId, NodePid}],
                ets:insert(RoutingTable, {BranchID, UpdatedNodeList})
        end;
    true -> ok
    end,
    {noreply, State}.