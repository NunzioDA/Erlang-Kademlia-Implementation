% --------------------------------------------------------------------
% Module: bootstrap_list_manager
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2025-01-23
% Description: This module implements the global 
% singleton server managing the list of bootstrap nodes.
% --------------------------------------------------------------------
-module(bootstrap_list_manager).

-export([init/1, handle_call/3, handle_cast/2, enroll_bootstrap/0, get_bootstrap_list/0]).
-export([start/0, location/0, enroll_erl_node/0, get_erl_nodes/0]).
-export([wait_for_initialization/0, kill/0]).

-behaviour(singleton).

% This function starts the bootstrap_list_manager
start() ->
    singleton:start(?MODULE, [], global)
.

% This function returns the location of the
% bootstrap_list_manager
location() ->
    singleton:location(global, ?MODULE)
.

% This function waits for the initialization of the
% bootstrap_list_manager
wait_for_initialization() ->
	singleton:wait_for_initialization(?MODULE)
.

% This function is used from erlang nodes
% to enroll themselves as erlang nodes
enroll_erl_node() ->
    ErlNode = node(),
    singleton:make_request(cast, {enroll_erl_node, ErlNode}, ?MODULE).

% This function is used from nodes
% to enroll themselves as bootstrap nodes
enroll_bootstrap() ->
    singleton:make_request(cast, {enroll_bootstrap, com:my_address()}, ?MODULE)
.

% This function returns the list of bootstrap nodes
get_bootstrap_list() ->
    {ok, BootstrapList} = singleton:make_request(call, {get_bootstrap_list}, ?MODULE),
    BootstrapList
.

get_erl_nodes() ->
    {ok, ErlNodesList} = singleton:make_request(call, {get_erl_nodes_list}, ?MODULE),
    ErlNodesList
.

% This function initializes the bootstrap_list_manager
init([ListenerPid]) ->
    singleton:notify_server_is_running(ListenerPid, ?MODULE),
    BootstrapList = [],
    ErlNodeList = [],
	{ok, {BootstrapList, ErlNodeList}}
.

% This function handles the get_bootstrap_list call
handle_call({get_bootstrap_list}, _, State) ->  
    {BootstrapList,_} = State,
	{reply, {ok,BootstrapList}, State}
;
% This function handles the get_erl_nodes_list call
% It returns the list of erlang nodes
handle_call({get_erl_nodes_list}, _, State) ->  
    {_,ErlNodes} = State,
	{reply, {ok,ErlNodes}, State}
.

% This function handles the enroll_bootstrap cast
% It adds the node in From to the list of bootstrap nodes
handle_cast({enroll_bootstrap,From}, State) ->
    {BootstrapList,ErlNodeList} = State,
	{noreply, {[From | BootstrapList], ErlNodeList}}
;
% This function handles the enroll_erl_node
% It adds the node to the list of erlang nodes
% if it is not already present
handle_cast({enroll_erl_node,Node}, State) ->
    {BootstrapList,ErlNodeList} = State,
    case lists:member(Node, ErlNodeList) of
        true -> 
            {noreply, {BootstrapList, ErlNodeList}};
        false -> 
            {noreply, {BootstrapList, [Node | ErlNodeList]}}
    end
.

% This function kills the bootstrap_list_manager
kill() ->
    Pid = ?MODULE:location(),
    exit(Pid, kill)
.

