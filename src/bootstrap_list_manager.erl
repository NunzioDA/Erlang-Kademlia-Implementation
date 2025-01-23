-module(bootstrap_list_manager).
-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, enroll_bootstrap/0, get_bootstrap_list/0]).
-export([start/0, start_server/1, location/0, register/0, notify_server_is_running/1]).
-export([wait_for_initialization/0]).

start() ->
    ListenerPid = self(),
	Pid = ?MODULE:location(),

	if Pid == undefined ->
    	?MODULE:start_server(ListenerPid);
	true ->
		?MODULE:notify_server_is_running(ListenerPid),
		{warning, "An instance of " ++ atom_to_list(?MODULE) ++ " is already running."}
	end
.

start_server(ListenerPid) ->
    {ok, Pid} = gen_server:start_link(?MODULE, [ListenerPid], []),
    Pid
.

location() ->
    global:whereis_name(?MODULE).

register() ->
    global:register_name(?MODULE, self()).

notify_server_is_running(ListenerPid)->
	ListenerPid ! {analytics_collector_running}.


% This function is used to wait for
% the analytics_collector to 
% finish the init function.
% Use this function only after using start/3 function
% passing self() as the third parameter.
wait_for_initialization() ->
	receive 
        {analytics_collector_running} ->
            ok
    end
.

enroll_bootstrap() ->
    Pid = ?MODULE:location(),

    if Pid == undefined ->
        {error, "The server is not running"};
    true ->
        gen_server:cast(Pid, {enroll_bootstrap, com:my_address()})
    end
.

get_bootstrap_list() ->
    Pid = ?MODULE:location(),

    if Pid == undefined ->
        [];
    true ->
        {ok, BootstrapList} = gen_server:call(Pid, {get_bootstrap_list}),
        BootstrapList
    end
.

init([ListenerPid]) ->
    ?MODULE:register(),

    ?MODULE:notify_server_is_running(ListenerPid),
    BootstrapList = [],
	{ok, BootstrapList}.

handle_call({get_bootstrap_list}, _, BootstrapList) ->    
	{reply, {ok,BootstrapList}, BootstrapList}.


handle_cast({enroll_bootstrap,From}, BootstrapList) ->
	{noreply, [From | BootstrapList]}.



