% --------------------------------------------------------------------
% Module: singleton
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2025-01-23
% Description: This module provides a generic singleton server based on gen_server.
% --------------------------------------------------------------------

-module(singleton).
-export([start/3, start_server/4, make_request/3, location/2, notify_server_is_running/2]).
-export([initialization_event_name/1, wait_for_initialization/1, is_alive/1]).

% ---------------------------------
% singleton callbacks
% ---------------------------------
%
% The following callbacks must be implemented by the module
%
% This function returns the location of the singleton server
% It should call singleton:location/2 function with the appropriate arguments:
% - Type can be either global or local
% - Module is the module implementing the singleton server
-callback location() -> 
    Pid :: pid().
%
% This function is called to wait for the singleton server 
% to finish the init function.
% It should call singleton:wait_for_initialization/1 function 
% with the appropriate arguments:
% - Module is the module implementing the singleton server
-callback wait_for_initialization() -> 
    Result :: term().

% This callback is used to check 
% if the singleton server is alive
% It should call singleton:is_alive/1 
% function passing 
% - Module is the module implementing the singleton server
-callback is_alive() -> 
    Result :: boolean().

% ---------------------------------
% gen_server callbacks and types
% ---------------------------------
-type from() ::	{Client :: pid(), Tag :: gen:reply_tag()}.

-callback init(Args :: term()) ->
    {ok, State :: term()} |
    {ok, State :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term()} |
    ignore |
    {error, Reason :: term()}.

-callback handle_call(Request :: term(), From :: from(),
                      State :: term()) ->
    {reply, Reply :: term(), NewState :: term()} |
    {reply, Reply :: term(), NewState :: term(),
     timeout() | hibernate | {continue, term()}} |
    {noreply, NewState :: term()} |
    {noreply, NewState :: term(),
     timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
    {stop, Reason :: term(), NewState :: term()}.

-callback handle_cast(Request :: term(), State :: term()) ->
    {noreply, NewState :: term()} |
    {noreply, NewState :: term(),
     timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), NewState :: term()}.

% This function starts the singleton server
% if it is not already running
start(Module, Args, Type) when is_atom(Module) ->
    ListenerPid = self(),
	Pid = ?MODULE:location(Type, Module),

	if Pid == undefined ->
    	?MODULE:start_server(Type, ListenerPid, Module, Args);
	true ->
		?MODULE:notify_server_is_running(ListenerPid, Module),
		{warning, "An instance of " ++ atom_to_list(Module) ++ " is already running."}
	end
.

% This function starts the gen_server
% and returns the Pid
start_server(Type, ListenerPid, Module, Args) ->
    {ok, Pid} = gen_server:start({Type, Module}, Module, [ListenerPid] ++ Args, []),
    Pid
.

% This function allows to make a request to the singleton server
% The server must be started before making requests 
% Type can be either call or cast
% Request is the request to be made
% Module is the module implementing the singleton server
make_request(Type, Request, Module) when is_atom(Type) ->
	Pid = Module:location(),
	if Pid == undefined ->
		throw({error, "Error: start the " ++ atom_to_list(Module) ++ " server before adding events"});
	true ->
		case Type of
			call -> gen_server:call(Pid, Request);
			cast -> gen_server:cast(Pid, Request);
            _ -> throw({error, "Error: invalid request type"})
		end
	end
.

% This function returns the location 
% of the singlet server
% Type can be either global or local
% Module is the module implementing the singleton server
location(Type, Module) ->
    case Type of
        global -> global:whereis_name(Module);
        local -> whereis(Module);
        _ -> throw({error, "Error: location type, must be either global or local"})
    end
.

% This function checks if the singleton server is alive
is_alive(Module) ->
    case Module:location() of
        undefined -> false;
        _ -> true
    end
.

% This function returns the initialization event name
initialization_event_name(Module) ->
    AtomInitializationEvent = atom_to_list(Module) ++ "_running",
    AtomInitializationEvent
.

% This function notifies the 
% listener that the server is running
notify_server_is_running(ListenerPid, Module)->
    AtomInitializationEvent = ?MODULE:initialization_event_name(Module),
	ListenerPid ! {AtomInitializationEvent}.

% This function is used to wait for
% the singleton server to 
% finish the init function.
% Use this function only after 
% using start/3 function.
wait_for_initialization(Module) ->
    AtomInitializationEvent = ?MODULE:initialization_event_name(Module),
	receive 
        {AtomInitializationEvent} ->
            ok
    end
.