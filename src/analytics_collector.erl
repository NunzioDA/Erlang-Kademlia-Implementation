% -----------------------------------------------------------------------------
% Module: analytics_collector
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-26
% Description: This module manages the analytics collector to collect analytics events
% from running processes.
% -----------------------------------------------------------------------------

-module(analytics_collector).
-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3]).
-export([start/0, register_bootstrap/1, get_bootstrap_list/0, started_join_procedure/1, finished_join_procedure/1, join_procedure_mean_time/0, get_unfinished_processes/0]).

% --------------------------------
% Starting methods
% --------------------------------

% This function is used to start the analytics collector.
% If an instance is already running it returns a warning.
% Otherwise it starts a new instance.
start() ->
	Pid = whereis(analytics_collector),

	if Pid == undefined ->
    	start_link();
	true ->
		{warning, "An instance of analytics_collector is already running."}
	end.
% This functions starts a gen_server process
start_link() ->
    {ok, Pid} = gen_server:start_link(?MODULE, [], []),
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
	StartMillis = erlang:monotonic_time(millisecond),
	add(Pid, started_join_procedure, StartMillis).
% This function is used to signal that a process finished
% the join_procedure
finished_join_procedure(Pid) ->
	EndMillis = erlang:monotonic_time(millisecond),
	add(Pid, finished_join_procedure, EndMillis).

register_bootstrap(Pid) ->
	add(Pid, bootstrap, 1).
%
%------------------------------------
% Results management
%------------------------------------
%
% This function is used to compute the join_procedure
% mean time based on the signaled events
join_procedure_mean_time() ->
	StartedTimes = get_events(started_join_procedure),
	FinishedTimes = get_events(finished_join_procedure),

	MeanTime = calculate_mean_time(StartedTimes, FinishedTimes),
	MeanTime.

get_unfinished_processes()->
	StartedTimes = get_events(started_join_procedure),
	FinishedTimes = get_events(finished_join_procedure),

	FilteredStartedTimes = [Pid || {Pid, _} <- StartedTimes, not lists:keymember(Pid, 1, FinishedTimes)],
	utils:print("~p", [length(FilteredStartedTimes)]),
	FilteredStartedTimes.

get_bootstrap_list() ->
	lists:foldl(
		fun({Pid,_}, Acc) ->
			[Pid|Acc]
		end,
		[],
		get_events(bootstrap)
	).

% This function is used to compute the mean time based on two
% lists, the start time and the end time.
% Each list is a list of tuples {Pid, time}
calculate_mean_time(StartedTimes, FinishedTimes) ->
	FilteredStartedTimes = [{Pid, Time} || {Pid, Time} <- StartedTimes, lists:keymember(Pid, 1, FinishedTimes)],

	SortedStart = lists:sort(
		fun({Key1, _}, {Key2, _}) ->
			Key1 > Key2
		end,
		FilteredStartedTimes
	),

	SortedFinish = lists:sort(
		fun({Key1, _}, {Key2, _}) ->
			Key1 > Key2
		end,
		FinishedTimes
	),

	Times = lists:zip(SortedStart, SortedFinish),

	TotalTime = lists:foldl(
		fun({{_, Start}, {_,End}}, Acc) -> Acc + (End - Start) end, 
		0, 
		Times
	),

	Count = length(Times),
	case Count of
		0 -> 0;
		_ -> TotalTime div Count
	end.
	

%-------------------------------------------
% This function is the generic function used to add new events.
add(ClientPid, EventType, Event) ->
	make_request(cast, {new_event, ClientPid, EventType, Event})
.

% This function is used to get the events list of a given type.
get_events(EventType) ->
	case ets:lookup(analytics, EventType) of
		[{_, List}] -> List;
		_ -> []
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
	register_new_event(Pid, EventType, Event),
	{noreply, State}.
% This function saves the event to the ets table
% named analytics.
register_new_event(Pid, EventType, Event) ->
	case ets:lookup(analytics, EventType) of
		[{_,EventList}] ->
			ets:lookup(analytics, EventType),
			NewEventList = EventList ++ [{Pid, Event}],
			ets:insert(analytics, {EventType, NewEventList});
		[] ->
			ets:insert(analytics, {EventType, [{Pid, Event}]})
	end
.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

