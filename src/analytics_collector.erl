% -----------------------------------------------------------------------------
% Module: analytics_collector
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-26
% Description: This module manages the analytics collector to collect analytics events
% 			   from running processes.
% -----------------------------------------------------------------------------

-module(analytics_collector).
-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, listen_for/1, notify_listeners/2, kill/0, enroll_process/1]).
-export([start/0, enroll_bootstrap/1, get_bootstrap_list/0, get_processes_list/0, started_join_procedure/1, get_started_join_processes/0, flush_join_events/0]).
-export([finished_join_procedure/1, join_procedure_mean_time/0, get_unfinished_processes/0, get_finished_join_processes/0]).
-export([start_link/0, add/3, get_events/1, make_request/2, calculate_mean_time/2, register_new_event/3, empty_event_list/1]).

% --------------------------------
% Starting methods
% --------------------------------

% This function is used to start the analytics collector.
% If an instance is already running it returns a warning.
% Otherwise it starts a new instance.
start() ->
	Pid = whereis(analytics_collector),

	if Pid == undefined ->
    	?MODULE:start_link();
	true ->
		{warning, "An instance of analytics_collector is already running."}
	end.
% This functions starts a gen_server process
start_link() ->
    {ok, Pid} = gen_server:start(?MODULE, [], []),
    Pid
.

%--------------------------------------------------
% Events management
%--------------------------------------------------
%
%------------------------------------
% Add event methods
%------------------------------------
%
% This function is used to signal that a process started
% the join_procedure
started_join_procedure(Pid) ->	
	?MODULE:add(Pid, started_join_procedure, 0).
% This function is used to signal that a process finished
% the join_procedure
finished_join_procedure(Pid) ->
	?MODULE:add(Pid, finished_join_procedure, 0).

enroll_bootstrap(Pid) ->
	?MODULE:add(Pid, bootstrap, 1).
enroll_process(Pid)->
	?MODULE:add(Pid, processes, 1).

%
%------------------------------------
% Results management
%------------------------------------
%
% This function is used to compute the join_procedure
% mean time based on the signaled events
join_procedure_mean_time() ->
	StartedTimes = ?MODULE:get_started_join_processes(),
	FinishedTimes = ?MODULE:get_finished_join_processes(),



	MeanTime = ?MODULE:calculate_mean_time(StartedTimes, FinishedTimes),
	MeanTime.
% This function return all the processes that haven't finished the
% join procedure
get_unfinished_processes()->
	StartedTimes = ?MODULE:get_events(started_join_procedure),
	FinishedTimes = ?MODULE:get_events(finished_join_procedure),

	FilteredStartedTimes = [Pid || {Pid, _, _} <- StartedTimes, not lists:keymember(Pid, 1, FinishedTimes)],
	FilteredStartedTimes.

% This function flushes the join procedure results
flush_join_events() ->
	empty_event_list(started_join_procedure),
	empty_event_list(finished_join_procedure).

get_started_join_processes() ->
	?MODULE:get_events(started_join_procedure).

get_finished_join_processes() ->
	?MODULE:get_events(finished_join_procedure).

get_bootstrap_list() ->
	lists:foldl(
		fun({Pid,_,_}, Acc) ->
			[Pid|Acc]
		end,
		[],
		?MODULE:get_events(bootstrap)
	).

get_processes_list() ->
		lists:foldl(
		fun({Pid,_,_}, Acc) ->
			[Pid|Acc]
		end,
		[],
		?MODULE:get_events(processes)
	).

% This function is used to compute the mean time based on two
% lists, the start time and the end time.
% Each list is a list of tuples {Pid, time}
calculate_mean_time(StartedTimes, FinishedTimes) ->
	FilteredStartedTimes = [{Pid, Value, Time} || {Pid, Value, Time} <- StartedTimes, lists:keymember(Pid, 1, FinishedTimes)],
	SortedStart = lists:sort(
		fun({Pid1, _,_}, {Pid2, _, _}) ->
			Pid1 > Pid2
		end,
		FilteredStartedTimes
	),

	SortedFinish = lists:sort(
		fun({Pid1, _, _}, {Pid2, _, _}) ->
			Pid1 > Pid2
		end,
		FinishedTimes
	),

	Times = lists:zip(SortedStart, SortedFinish),

	TotalTime = lists:foldl(
		fun({{_, _, Start}, {_,_,End}}, Acc) -> Acc + (End - Start) end, 
		0, 
		Times
	),

	Count = length(Times),
	case Count of
		0 -> 0;
		_ -> TotalTime div Count
	end.

% ------------------------------------------
% LISTENERS MANAGEMENT
% ------------------------------------------
listen_for(EventType) ->
	Pid = self(),
	ServerPid = whereis(analytics_collector),
	gen_server:cast(ServerPid, {new_listener, Pid, EventType}).


% -------------------------------------------	
% GENERIC FUNCTIONS
% -------------------------------------------
% This function is the generic function used to add new events.
add(ClientPid, EventType, Event) ->
	?MODULE:make_request(cast, {new_event, ClientPid, EventType, Event})
.

% This function is used to get the events list of a given type.
get_events(EventType) ->
	case ets:lookup(analytics, EventType) of
		[{_, List}] -> List;
		_ -> []
	end.

% This function is used to notify enrolled event listeners
notify_listeners(EventType, Event) ->
	case get(listeners) of
		undefined -> 
			ok;
		ListenersMap ->
			case maps:is_key(EventType, ListenersMap) of
				true ->
					EventListeners = maps:get(EventType, ListenersMap),
					lists:foreach(
						fun(Pid) ->
							Pid ! {event_notification, EventType, Event}
						end,
						EventListeners
					);
				false -> ok
			end
	end.

% This function allows to make a request to the analytics server
% analytics server must be started before making requests
make_request(Type, Request) ->
	Pid = whereis(analytics_collector),
	if Pid == undefined ->
		throw({error, "Error: analytics_collector must to be started before an event can be added"});
	true ->
		case Type of
			call -> gen_server:call(Pid, Request);
			cast -> gen_server:cast(Pid, Request)
		end
	end
.
% This function is called to initialize the gen_server.
% It registers the analytics_collector Pid and creates the analytics ets to
% collect data.
init([]) ->
	register(analytics_collector, self()),
	Analytics = ets:new(analytics, [set, public, named_table]),
	{ok, Analytics}.

handle_call(_Request, _From, State) ->
	{reply, ok, State}.

% This clause handle the registration of a generic event
handle_cast({new_event, Pid, EventType, Event}, State) ->
	?MODULE:register_new_event(Pid, EventType, Event),
	{noreply, State};

% This clause handle the registration of an event listener
handle_cast({new_listener, Pid, EventType}, State) ->
	ListenersMap = get(listeners),
	if(ListenersMap == undefined) ->
		put(listeners, #{EventType=>[Pid]});
	true ->
		EventListeners = maps:get(EventType, ListenersMap),
		NewEventListeners = [Pid|EventListeners],
		NewListenersMap = maps:put(EventType, NewEventListeners, ListenersMap),
		put(listeners, NewListenersMap)
	end,
	{noreply, State}.

empty_event_list(EventType) ->
	ets:insert(analytics, {EventType, []}).

% This function saves the event to the ets table
% named analytics.
register_new_event(Pid, EventType, Event) ->
	Millis = erlang:monotonic_time(millisecond),
	NewRecord = {Pid, Event, Millis},
	case ets:lookup(analytics, EventType) of
		[{_,EventList}] ->
			ets:lookup(analytics, EventType),
			NewEventList = EventList ++ [NewRecord],
			ets:insert(analytics, {EventType, NewEventList});
		[] ->
			ets:insert(analytics, {EventType, [NewRecord]})
	end,
	?MODULE:notify_listeners(EventType, NewRecord)
.


kill() ->
	case whereis(analytics_collector) of
		undefined -> utils:print("There is not any instance of Analytic Collector running");
		Pid -> 
			exit(Pid, kill),
			ets:delete(analytics)
	end.
