% -----------------------------------------------------------------------------
% Module: analytics_collector
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-26
% Description: This module manages the analytics collector to collect analytics events
% 			   from running processes.
% -----------------------------------------------------------------------------

-module(analytics_collector).
-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, listen_for/1, notify_listeners/2, kill/0, enroll_node/1]).
-export([start/0, enroll_bootstrap/1, get_bootstrap_list/0, get_node_list/0, started_join_procedure/0, get_started_join_nodes/0, flush_join_events/0]).
-export([finished_join_procedure/1, join_procedure_mean_time/0, get_unfinished_join_nodes/0, get_finished_join_nodes/0]).
-export([start_link/0, add/3, get_events/1, make_request/2, calculate_mean_time/2, register_new_event/3, empty_event_list/1]).
-export([started_time_based_event/1, started_lookup/0, finished_time_based_event/2, finished_lookup/1, lookup_mean_time/0, get_finished_lookup/0]).

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

% This function is used to enroll a process as 
% a bootstrap node
enroll_bootstrap(Pid) ->
	?MODULE:add(Pid, bootstrap, 1).
% This functin is used to enrol a process as 
% a node
enroll_node(Pid)->
	?MODULE:add(Pid, node, 1).


% This function is used to signal that a process started
% the join_procedure
started_join_procedure() ->
	?MODULE:started_time_based_event(started_join_procedure).

% This function is used to signal that a process finished
% the join_procedure
finished_join_procedure(EventId) ->
	?MODULE:finished_time_based_event(finished_join_procedure, EventId).

started_lookup() ->
	?MODULE:started_time_based_event(started_lookup).

finished_lookup(EventId) ->
	?MODULE:finished_time_based_event(finished_lookup, EventId).


% This function is used to signal the start of a time based event.
% It generates a unique integer that will be used to associate 
% start events with finish events.
started_time_based_event(Event) ->
	Pid = com:my_address(),
	UniqueInteger = integer_to_list(erlang:unique_integer([positive])),
	?MODULE:add(Pid, Event, UniqueInteger),
	UniqueInteger.
% This function is used to signal the end of a time based event.
% It requires the EventId that is the unique integer generated in
% started_time_based_event
finished_time_based_event(Event, EventId) ->
	Pid = com:my_address(),
	?MODULE:add(Pid, Event, EventId).	

%------------------------------------
% Results management
%------------------------------------
%
lookup_mean_time() ->
	StartedTimes = ?MODULE:get_events(started_lookup),
	FinishedTimes = ?MODULE:get_events(finished_lookup),

	MeanTime = ?MODULE:calculate_mean_time(StartedTimes, FinishedTimes),
	MeanTime.
% This function is used to compute the join_procedure
% mean time based on the signaled events
join_procedure_mean_time() ->
	StartedTimes = ?MODULE:get_started_join_nodes(),
	FinishedTimes = ?MODULE:get_finished_join_nodes(),

	MeanTime = ?MODULE:calculate_mean_time(StartedTimes, FinishedTimes),
	MeanTime.
% This function return all the processes that haven't finished the
% join procedure
get_unfinished_join_nodes()->
	StartedTimes = ?MODULE:get_events(started_join_procedure),
	FinishedTimes = ?MODULE:get_events(finished_join_procedure),

	FilteredStartedTimes = [Pid || {Pid, _, _} <- StartedTimes, not lists:keymember(Pid, 1, FinishedTimes)],
	FilteredStartedTimes.

% This function flushes the join procedure results
flush_join_events() ->
	empty_event_list(started_join_procedure),
	empty_event_list(finished_join_procedure).

get_started_join_nodes() ->
	?MODULE:get_events(started_join_procedure).

get_finished_join_nodes() ->
	?MODULE:get_events(finished_join_procedure).

get_finished_lookup() ->
	?MODULE:get_events(finished_lookup).


get_bootstrap_list() ->
	lists:foldl(
		fun({Pid,_,_}, Acc) ->
			[Pid|Acc]
		end,
		[],
		?MODULE:get_events(bootstrap)
	).

get_node_list() ->
		lists:foldl(
		fun({Pid,_,_}, Acc) ->
			[Pid|Acc]
		end,
		[],
		?MODULE:get_events(node)
	).

% This function is used to compute the mean time based on two
% lists, the start times and the end times.
% Each list is a list of tuples {Pid, time}
calculate_mean_time(StartedTimes, FinishedTimes) ->
	% Getting all the events in start times that are contained in finish times 
	FilteredStartedTimes = [{Pid, Value, Time} || {Pid, Value, Time} <- StartedTimes, lists:keymember(Value, 2, FinishedTimes)],
	% Getting all the events in finished times that are contained in filtered start times
	FilteredFinishTimes = [{Pid, Value, Time} || {Pid, Value, Time} <- FinishedTimes, lists:keymember(Value, 2, FilteredStartedTimes)],
	
	% Sorting the lists so we can later zip them correctly
	SortedStart = lists:sort(
		fun({_, Id1, _}, {_, Id2, _}) ->
			Id1 > Id2
		end,
		FilteredStartedTimes
	),

	SortedFinish = lists:sort(
		fun({_, Id1, _}, {_, Id2, _}) ->
			Id1 > Id2
		end,
		FilteredFinishTimes
	),

	% Zip the two lists and compute the total elapsed times
	Times = lists:zip(SortedStart, SortedFinish),
	TotalTime = lists:foldl(
		fun({{_, _, Start}, {_,_,End}}, Acc) -> Acc + (End - Start) end, 
		0, 
		Times
	),

	% Compute the mean time
	Count = length(Times),
	case Count of
		0 -> 0;
		_ -> TotalTime div Count
	end.


% ------------------------------------------
% ANALYTICS COLLECTOR BASE FUNCTIONALITY
% ------------------------------------------
%
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
		case (maps:is_key(EventType,ListenersMap)) of
			true->
				EventListeners = maps:get(EventType, ListenersMap),
				NewEventListeners = [Pid|EventListeners];
			false ->
				NewEventListeners = [Pid]
		end,
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
