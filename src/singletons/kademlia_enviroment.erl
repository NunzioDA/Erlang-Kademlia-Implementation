% --------------------------------------------------------------------
% Module: kademlia_enviroment
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2025-01-23
% Description: This module implements the global 
% singleton server managing the kademlia enviroment.
% --------------------------------------------------------------------
-module(kademlia_enviroment).

-export([init/1, handle_call/3, handle_cast/2, enroll_bootstrap/0, get_bootstrap_list/0]).
-export([start/2, location/0, enroll_erl_node/0, get_erl_nodes/0, is_alive/0]).
-export([wait_for_initialization/0, kill/0,get_simulation_parameters/0]).

-behaviour(singleton).

% This function starts the kademlia_enviroment
start(K, T) ->
    singleton:start(?MODULE, [K, T], global)
.

% This function returns the location of the
% kademlia_enviroment
location() ->
    singleton:location(global, ?MODULE)
.

% This function waits for the initialization of the
% kademlia_enviroment
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

% This function returns the list of erlang nodes
get_erl_nodes() ->
    {ok, ErlNodesList} = singleton:make_request(call, {get_erl_nodes_list}, ?MODULE),
    ErlNodesList
.

% This function is used to make a request
% to the kademlia_enviroment to get the current
% simulation parameters K and T
get_simulation_parameters() ->
	singleton:make_request(call, {get_simulation_parameters}, ?MODULE)
.

% This function initializes the kademlia_enviroment
init([ListenerPid, K, T]) ->
    singleton:notify_server_is_running(ListenerPid, ?MODULE),
    BootstrapList = [],
    ErlNodeList = [],
	{ok, {BootstrapList, ErlNodeList, K, T}}
.

% This function handles the get_bootstrap_list call
handle_call({get_bootstrap_list}, _, State) ->  
    {BootstrapList,_, _, _} = State,
	{reply, {ok,BootstrapList}, State}
;
% This function handles the get_erl_nodes_list call
% It returns the list of erlang nodes
handle_call({get_erl_nodes_list}, _, State) ->  
    {_,ErlNodes, _, _} = State,
	{reply, {ok,ErlNodes}, State}
;
% This function is used to handle the requests
% made to the kademlia_enviroment requiring 
% the simulation parameters K and T
handle_call({get_simulation_parameters}, _From, State) ->
	{_,_,K,T} = State,
	{reply, {K,T}, State}
.

% This function handles the enroll_bootstrap cast
% It adds the node in From to the list of bootstrap nodes
handle_cast({enroll_bootstrap,From}, State) ->
    {BootstrapList,ErlNodeList, K, T} = State,
	{noreply, {[From | BootstrapList], ErlNodeList, K, T}}
;
% This function handles the enroll_erl_node
% It adds the node to the list of erlang nodes
% if it is not already present
handle_cast({enroll_erl_node,Node}, State) ->
    {BootstrapList,ErlNodeList, K, T} = State,
    case lists:member(Node, ErlNodeList) of
        true -> 
            {noreply, {BootstrapList, ErlNodeList, K, T}};
        false -> 
            {noreply, {BootstrapList, [Node | ErlNodeList], K, T}}
    end
.

% This function checks if the analytics collector is alive
is_alive() ->
	singleton:is_alive(?MODULE)
.

% This function kills the kademlia_enviroment
kill() ->
    case ?MODULE:location() of
        undefined -> ok;
        Pid ->
            exit(Pid, kill)
    end
.

