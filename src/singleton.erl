-module(singleton).
-export([start/3, start_server/3, make_request/3, location/2, registerSingleton/3, notify_server_is_running/2, wait_for_initialization/1]).

-type from() ::	{Client :: pid(), Tag :: gen:reply_tag()}.

-callback location() -> 
    Pid :: pid().
-callback wait_for_initialization() -> 
    Result :: term().

% Ensuring the module initializes
% gen_server behaviour
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

start(Module, Args, Type) when is_atom(Module) ->
    ListenerPid = self(),
	Pid = ?MODULE:location(Type, Module),

	if Pid == undefined ->
    	NewSingletonPid = ?MODULE:start_server(ListenerPid, Module, Args),
        ?MODULE:registerSingleton(Type, NewSingletonPid, Module);
	true ->
		?MODULE:notify_server_is_running(ListenerPid, Module),
		{warning, "An instance of " ++ atom_to_list(Module) ++ " is already running."}
	end
.

start_server(ListenerPid, Module, Args) ->
    {ok, Pid} = gen_server:start(Module, [ListenerPid] ++ Args, []),
    Pid
.

% This function allows to make a request to the analytics server
% analytics server must be started before making requests
make_request(Type, Request, Module) when is_atom(Type) ->
	Pid = Module:location(),
	if Pid == undefined ->
		throw({error, "Error: start the server before adding events"});
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
location(Type, Module) ->
    case Type of
        global -> global:whereis_name(Module);
        local -> whereis(Module);
        _ -> throw({error, "Error: location type, must be either global or local"})
    end
.

% This function registers the singleton server
registerSingleton(Type, Pid, Module) ->
    case Type of
        global -> global:register_name(Module, Pid);
        local -> register(Module, Pid);
        _ -> throw({error, "Error: location type, must be either global or local"})
    end
.

initialization_event(Module) ->
    AtomInitializationEvent = atom_to_list(Module) ++ "_running",
    AtomInitializationEvent
.

% This function notifies the 
% listener that the server is running
notify_server_is_running(ListenerPid, Module)->
    AtomInitializationEvent = initialization_event(Module),
	ListenerPid ! {AtomInitializationEvent}.

% This function is used to wait for
% the analytics_collector to 
% finish the init function.
% Use this function only after using start/3 function
% passing self() as the third parameter.
wait_for_initialization(Module) ->
    AtomInitializationEvent = initialization_event(Module),
	receive 
        {AtomInitializationEvent} ->
            ok
    end
.