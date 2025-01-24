% ----------------------------------------
% Module: bootstrap_list_manager
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2025-01-23
% Description: This module implements the global 
% singleton server managing the list of bootstrap nodes.
% --------------------------------------------------------------------
-module(bootstrap_list_manager).

-export([init/1, handle_call/3, handle_cast/2, enroll_bootstrap/0, get_bootstrap_list/0]).
-export([start/0, location/0]).
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

% This function initializes the bootstrap_list_manager
init([ListenerPid]) ->
    singleton:notify_server_is_running(ListenerPid, ?MODULE),
    BootstrapList = [],
	{ok, BootstrapList}.

% This function handles the get_bootstrap_list call
handle_call({get_bootstrap_list}, _, BootstrapList) ->    
	{reply, {ok,BootstrapList}, BootstrapList}.

% This function handles the enroll_bootstrap cast
% It adds the node in From to the list of bootstrap nodes
handle_cast({enroll_bootstrap,From}, BootstrapList) ->
	{noreply, [From | BootstrapList]}.

% This function kills the bootstrap_list_manager
kill() ->
    Pid = ?MODULE:location(),
    exit(Pid, kill)
.

