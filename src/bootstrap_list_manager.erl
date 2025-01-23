-module(bootstrap_list_manager).
-behaviour(singleton).

-export([init/1, handle_call/3, handle_cast/2, enroll_bootstrap/0, get_bootstrap_list/0]).
-export([start/0, location/0]).
-export([wait_for_initialization/0, kill/0]).


start() ->
    singleton:start(?MODULE, [], global)
.

location() ->
    singleton:location(global, ?MODULE)
.

wait_for_initialization() ->
	singleton:wait_for_initialization(?MODULE)
.

enroll_bootstrap() ->
    singleton:make_request(cast, {enroll_bootstrap, com:my_address()}, ?MODULE)
.

get_bootstrap_list() ->
    {ok, BootstrapList} = singleton:make_request(call, {get_bootstrap_list}, ?MODULE),
    BootstrapList
.

init([ListenerPid]) ->
    singleton:notify_server_is_running(ListenerPid, ?MODULE),
    BootstrapList = [],
	{ok, BootstrapList}.

handle_call({get_bootstrap_list}, _, BootstrapList) ->    
	{reply, {ok,BootstrapList}, BootstrapList}.


handle_cast({enroll_bootstrap,From}, BootstrapList) ->
	{noreply, [From | BootstrapList]}.

kill() ->
    Pid = ?MODULE:location(),
    exit(Pid, kill)
.

