% -----------------------------------------------------------------------------
% Module: analytics_collector
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-26
% Description: This module manages the analytics collector to collect analytics events
% 			   from running processes.
% -----------------------------------------------------------------------------

-module(analytics_collector).

-export([init/1, handle_call/3, handle_cast/2, listen_for/1, notify_listeners/3, kill/0, enroll_node/0, stored_value/1]).
-export([start/0, get_node_list/0, started_join_procedure/0, get_started_join_nodes/0, flush_join_events/0]).
-export([finished_join_procedure/1, get_unfinished_join_nodes/0, get_finished_join_nodes/0, flush_lookups_events/0, shut/0]).
-export([add/2, get_events/1, make_request/2, calculate_mean_time/2, register_new_event/4, empty_event_list/1]).
-export([started_time_based_event/1, started_lookup/0, finished_time_based_event/2, finished_lookup/1, lookup_mean_time/0]).
-export([get_started_lookup/0, join_procedure_mean_time/0, get_nodes_that_stored/1,get_finished_lookup/0, aggregate_results/1]).
-export([get_started_distribute/0,get_finished_distribute/0, flush_distribute_events/0, started_distribute/0, finished_distribute/1]).
-export([distribute_mean_time/0, flush_nodes_that_stored/0, time_based_event_mean_time/2, is_alive/0]).
-export([started_filling_routing_table/0, finished_filling_routing_table/1, filling_routing_table_mean_time/0, talk/0, location/0]).
-export([get_started_filling_routing_table_nodes/0, get_finished_filling_routing_table_nodes/0, notify_server_is_running/1, aggregate_call/2]).
-export([flush_filling_routing_table_events/0, get_unfinished_filling_routing_table_nodes/0, wait_for_initialization/0, create_events_table/0]).

-behaviour(singleton).
% --------------------------------
% Starting methods
% --------------------------------

% This function is used to start the analytics collector.
% If an instance is already running it returns a warning.
% Otherwise it starts a new instance.
start() ->
	singleton:start(?MODULE, [], local)
.

%--------------------------------------------------
% Events management
%--------------------------------------------------
%
%------------------------------------
% Add event methods
%------------------------------------

% This functin is used to enrol a process as 
% a node
enroll_node()->
	?MODULE:add(node, 1)
.

%--------------------------------------------
% Join
%
% Join events are not treated as time_based events
% using started_time_based_event and finished_time_based_event
% to improve performances
%
% This function is used to signal that a process started
% the join_procedure
started_join_procedure() ->
	erlang:monotonic_time(millisecond)
	% ?MODULE:started_time_based_event(started_join_procedure)
.

% This function is used to signal that a process finished
% the join_procedure
finished_join_procedure(Start) ->
	End = erlang:monotonic_time(millisecond),
	Elapsed = End - Start,
	?MODULE:add(finished_join_procedure, Elapsed)
	% ?MODULE:finished_time_based_event(finished_join_procedure, EventId)
.

%--------------------------------------------
% Fill routing table
%
% This function is used to signal that a process started
% the filling_routing_table procedure
started_filling_routing_table() ->
	?MODULE:started_time_based_event(started_filling_routing_table)
.

% This function is used to signal that a process finished
% the filling_routing_table procedure
finished_filling_routing_table(EventId) ->
	?MODULE:finished_time_based_event(finished_filling_routing_table, EventId)
.

%--------------------------------------------
% Lookup
%
% This function is used to signal that a process started
% the lookup procedure
started_lookup() ->
	?MODULE:started_time_based_event(started_lookup)
.

% This function is used to signal that a process finished
% the lookup procedure
finished_lookup(EventId) ->
	?MODULE:finished_time_based_event(finished_lookup, EventId)
.

%--------------------------------------------
% Distribute
%
% This function is used to signal that a process started
% the distribution procedure
started_distribute() ->
	?MODULE:started_time_based_event(started_distribute)
.

% This function is used to signal that a process finished
% the distribution procedure
finished_distribute(EventId) ->
	?MODULE:finished_time_based_event(finished_distribute, EventId)
.

%--------------------------------------------
% Store
%
% This function is used to signal a node saved the value 
% relative to a specific key
stored_value(Key) ->
	EventId = erlang:unique_integer([positive]),
	?MODULE:add(stored_value, {EventId, Key})
.

%------------------------------------
% Results management
%------------------------------------
%
%--------------------------------------------
% Join
%
% Join events are not treated as time_based 
% events using time_based_event_mean_time 
% to improve performances
%--------------------------------------------
%
% This function is used to compute the join_procedure
% mean time based on the signaled events
join_procedure_mean_time() ->
	FinishedTimes = ?MODULE:get_events(finished_join_procedure),

	case length(FinishedTimes) of
		0 -> 0;
		Len -> 
			TotalTime = lists:foldl(
				fun({_,Elapsed,_},Total) ->
					Total + Elapsed
				end,
				0,
				FinishedTimes	
			),
			Result = TotalTime div Len,
			Result
	end

	% ?MODULE:time_based_event_mean_time(started_join_procedure, finished_join_procedure)
.

% This function return all the processes that haven't finished the
% join procedure
get_unfinished_join_nodes()->
	StartedTimes = ?MODULE:get_events(started_join_procedure),
	FinishedTimes = ?MODULE:get_events(finished_join_procedure),

	FilteredStartedTimes = [Pid || {Pid, _, _} <- StartedTimes, not lists:keymember(Pid, 1, FinishedTimes)],
	FilteredStartedTimes
.

% This function returns all the processes that have
% started the join procedure
get_started_join_nodes() ->
	?MODULE:get_events(started_join_procedure)
.

% This function returns all the processes that have
% finished the join procedure
get_finished_join_nodes() ->
	?MODULE:get_events(finished_join_procedure)
.

% This function flushes the join procedure results
flush_join_events() ->
	?MODULE:empty_event_list(started_join_procedure),
	?MODULE:empty_event_list(finished_join_procedure)
.

%--------------------------------------------
% Fill routing table
%
% This function is used to compute the filling_routing_table
% mean time based on the signaled events
filling_routing_table_mean_time() ->
	?MODULE:time_based_event_mean_time(started_filling_routing_table, finished_filling_routing_table)
.

% This function returns all the processes that have
% started the filling_routing_table procedure
get_started_filling_routing_table_nodes() ->
	?MODULE:get_events(started_filling_routing_table)
.

% This function returns all the processes that have
% finished the filling_routing_table procedure
get_finished_filling_routing_table_nodes() ->
	?MODULE:get_events(finished_filling_routing_table)
.

% This function return all the processes that haven't finished
% filling their routing table
get_unfinished_filling_routing_table_nodes()->
	StartedTimes = ?MODULE:get_events(started_filling_routing_table),
	FinishedTimes = ?MODULE:get_events(finished_filling_routing_table),

	FilteredStartedTimes = [Pid || {Pid, _, _} <- StartedTimes, not lists:keymember(Pid, 1, FinishedTimes)],
	FilteredStartedTimes
.

% This function flushes the fill routing table procedure results
flush_filling_routing_table_events() ->
	?MODULE:empty_event_list(started_filling_routing_table),
	?MODULE:empty_event_list(finished_filling_routing_table)
.

%--------------------------------------------
% Lookup
%
% This function computes the lookup mean time
lookup_mean_time() ->
	?MODULE:time_based_event_mean_time(started_lookup, finished_lookup)
.

% This function returns all the processes that have
% started the lookup procedure
get_started_lookup() ->
	?MODULE:get_events(started_lookup)
.

% This function returns all the processes that have
% finished the lookup procedure
get_finished_lookup() ->
	?MODULE:get_events(finished_lookup)
.

% This function flushes the lookup procedure results
flush_lookups_events() ->
	?MODULE:empty_event_list(started_lookup),
	?MODULE:empty_event_list(finished_lookup)
.

%--------------------------------------------
% Distribute
%
% This function returns all the processes that have
% started the lookup procedure
get_started_distribute() ->
	?MODULE:get_events(started_distribute)
.

% This function returns all the processes that have
% finished the lookup procedure
get_finished_distribute() ->
	?MODULE:get_events(finished_distribute)
.

% This function flushes the lookup procedure results
flush_distribute_events() ->
	?MODULE:empty_event_list(started_distribute),
	?MODULE:empty_event_list(finished_distribute)
.

% This function is used to compute the mean time of the distribution procedure. 
distribute_mean_time() ->
	time_based_event_mean_time(started_distribute,finished_distribute).

%--------------------------------------------
% Processes

% This function returns all the processes that have
% enrolled as nodes
get_node_list() ->
		lists:foldl(
		fun({Pid,_,_}, Acc) ->
			[Pid|Acc]
		end,
		[],
		?MODULE:get_events(node)
	)
.

%--------------------------------------------
% Store
%
% This function returns all the processes that have
% stored the value relative to a specific key
get_nodes_that_stored(Key) ->
	StoreEvents = ?MODULE:get_events(stored_value),
	KeyStoreEvents = [Pid || {Pid,{_,SavedKey}, _} <- StoreEvents, SavedKey == Key],
	NoDuplicate = utils:remove_duplicates(KeyStoreEvents),
	NoDuplicate
.

% This function flushes the stored_value events
flush_nodes_that_stored() ->
	?MODULE:empty_event_list(stored_value)
.

% This function is used to compute the mean time based on two
% lists, the start times and the end times.
% Each list is a list of tuples {Pid, time}
calculate_mean_time(StartedTimes, FinishedTimes) ->
	StartedTriplette = lists:foldl(
		fun({Pid, {Value, EventTime}, _}, Acc) ->
			[{Pid, Value, EventTime}] ++ Acc
		end,
		[],
		StartedTimes
	),

	FinishedTriplette = lists:foldl(
		fun({Pid, {Value, EventTime}, _}, Acc) ->
			[{Pid, Value, EventTime}] ++ Acc
		end,
		[],
		FinishedTimes
	),

	% Getting all the events in start times that are contained in finish times 
	FilteredStartedTimes = [{Pid, Value, Time} || {Pid, Value, Time} <- StartedTriplette, lists:keymember(Value, 2, FinishedTriplette)],
	% Getting all the events in finished times that are contained in filtered start times
	FilteredFinishTimes = [{Pid, Value, Time} || {Pid, Value, Time} <- FinishedTriplette, lists:keymember(Value, 2, FilteredStartedTimes)],
	
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
	end
.


% ------------------------------------------
% ANALYTICS COLLECTOR BASE FUNCTIONALITY
% ------------------------------------------
%
% ------------------------------------------
% LISTENERS MANAGEMENT
% ------------------------------------------
listen_for(EventType) ->
	Pid = self(),
	ServerPid = ?MODULE:location(),
	gen_server:cast(ServerPid, {new_listener, Pid, EventType})
.

% ------------------------------------------
% AGGREGATION FUNCTIONS
% ------------------------------------------
%
% 
aggregate_results(Function) ->
	Results = ?MODULE:aggregate_call(Function, []),
	Sum = lists:foldl(
		fun(Result, Acc) -> 
			Result + Acc
		end,
		0,
		Results	
	),
	case length(Results) of
		0 -> 0;
		_ -> Sum div length(Results)
	end
.
% This function is used to make an aggregate call
% to the analytics_collector on all the erlang nodes
aggregate_call(Function, Args) ->
	ErlNodes = kademlia_enviroment:get_erl_nodes(),
	Results = lists:foldl(
		fun(Node, Acc) ->			
			case net_adm:ping(Node) of
				% Is alive
				pong ->
					Acc ++ [rpc:call(Node, analytics_collector, Function, Args)];
				% Is not alive
				_ -> Acc
			end
		end,
		[],
		ErlNodes
	),
	Results
.


% -------------------------------------------	
% GENERIC FUNCTIONS
% -------------------------------------------
%
create_events_table() ->
	ets:new(analytics, [named_table, set, public]).

% This function is used to get the events list of a given type.
get_events(EventType) ->
	case ets:lookup(analytics, EventType) of
		[{_, List}] -> List;
		_ -> []
	end
.

% This function is used to empty 
% the event list of a given type
empty_event_list(EventType) ->
	ets:insert(analytics, {EventType, []})
.

% This function saves the event to the ets table
% named analytics.
register_new_event(Pid, EventType, EventValue, ListenersMap) ->
	Millis = erlang:monotonic_time(millisecond),
	NewRecord = {Pid, EventValue, Millis},
	case ets:lookup(analytics, EventType) of
		[{_, EventList}] ->
			NewEventList = EventList ++ [NewRecord],
			ets:insert(analytics, {EventType, NewEventList});
		[] ->
			ets:insert(analytics, {EventType, [NewRecord]})
	end,
	?MODULE:notify_listeners(EventType, NewRecord, ListenersMap)
.

% This request is used for debugging purposes
% setting verbose to true
talk() -> 
	?MODULE:make_request(cast, {talk}).

% This request is used for debugging purposes
% setting verbose to false
shut() -> 
	?MODULE:make_request(cast, {shut}).

% This function is the generic function used to add new events.
add(EventType, EventValue) ->
	ClientPid = com:my_address(),
	?MODULE:make_request(cast, {new_event, ClientPid, EventType, EventValue})
.

% This function is used to signal the start of a time based event.
% It generates a unique integer that will be used to associate 
% start events with finish events.
started_time_based_event(EventType) ->
	EventId = erlang:unique_integer([positive]),
	CurrentTime = erlang:monotonic_time(millisecond),
	?MODULE:add(EventType, {EventId,CurrentTime}),
	EventId
.

% This function is used to signal the end of a time based event.
% It requires the EventId that is the unique integer generated in
% started_time_based_event
finished_time_based_event(EventType, EventId) ->
	CurrentTime = erlang:monotonic_time(millisecond),
	?MODULE:add(EventType, {EventId,CurrentTime})
.	

% This function is used to compute time based event
% mean time using calculate_mean_time
time_based_event_mean_time(Started,Finished) ->
	StartedTimes = ?MODULE:get_events(Started),
	FinishedTimes = ?MODULE:get_events(Finished),

	MeanTime = ?MODULE:calculate_mean_time(StartedTimes, FinishedTimes),
	MeanTime
.

% This function is used to notify enrolled event listeners
notify_listeners(EventType, EventValue, ListenersMap) ->
	case ListenersMap of
		undefined -> 
			ok;
		ListenersMap ->
			case maps:is_key(EventType, ListenersMap) of
				true ->
					EventListeners = maps:get(EventType, ListenersMap),
					lists:foreach(
						fun(Pid) ->
							Pid ! {event_notification, EventType, EventValue}
						end,
						EventListeners
					);
				false -> ok
			end
	end
.

% This function allows to make a request to the analytics server
% analytics server must be started before making requests
make_request(Type, Request) ->
	Pid = ?MODULE:location(),
	if Pid == undefined ->
		throw({error, "Error: start the analytics_collector before adding events"});
	true ->
		case Type of
			call -> gen_server:call(Pid, Request);
			cast -> gen_server:cast(Pid, Request)
		end
	end
.
% This function is used to notify that the server is running
notify_server_is_running(ListenerPid)->
	ListenerPid ! {analytics_collector_running}.

% This function is called to initialize the gen_server.
% It registers the analytics_collector Pid and creates the analytics ets to
% collect data.
init([ListenerPid]) ->
	?MODULE:create_events_table(),
	ListenersMap = #{},
	kademlia_enviroment:enroll_erl_node(),
	singleton:notify_server_is_running(ListenerPid, ?MODULE),
	{ok, {ListenersMap}}
.

handle_call(_R,_From,State) ->
	{reply, ok, State}
.

% This clause handle the registration of a generic event
handle_cast({new_event, Pid, EventType, Event}, State) ->
	{ListenersMap} = State,
	utils:debug_print("ADDING ~p",[EventType]),
	?MODULE:register_new_event(Pid, EventType, Event, ListenersMap),
	{noreply, State};
% This request is used for debugging purposes
% setting verbose to true
handle_cast({talk}, State) ->
	utils:set_verbose(true),
	{noreply, State};
% This request is used for debugging purposes
% setting verbose to false
handle_cast({shut}, State) ->
	utils:set_verbose(false),
	{noreply, State};
% This clause handle the registration of an event listener
handle_cast({new_listener, Pid, EventType}, State) ->
	{ListenersMap} = State,
	if(ListenersMap == undefined) ->
		NewListenersMap = #{EventType=>[Pid]};
	true ->
		case (maps:is_key(EventType,ListenersMap)) of
			true->
				EventListeners = maps:get(EventType, ListenersMap),
				NewEventListeners = [Pid|EventListeners];
			false ->
				NewEventListeners = [Pid]
		end,
		NewListenersMap = maps:put(EventType, NewEventListeners, ListenersMap)
	end,
	{noreply, {NewListenersMap}}
.

% This function is used to wait for
% the analytics_collector to 
% finish the init function.
% Use this function only after using start/3 function
% passing self() as the third parameter.
wait_for_initialization() ->
	singleton:wait_for_initialization(?MODULE)
.

% This function is used to kill the analytics collector
% if it is running.
kill() ->
	case ?MODULE:location() of
		undefined -> utils:print("There is not any instance of Analytic Collector running");
		Pid -> 
			exit(Pid, kill),
			ets:delete(analytics)
	end
.

% This function is used to get 
% the Pid of the analytics collector 
location() ->
    singleton:location(local, ?MODULE)
.

% This function checks if the analytics collector is alive
is_alive() ->
	singleton:is_alive(?MODULE)
.