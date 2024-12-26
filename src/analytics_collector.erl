-module(analytics_collector).
-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3]).
-export([start/0]).

start() ->
    start_link().

start_link() ->
    {ok, Pid} = gen_server:start_link(?MODULE, [], []),
    Pid
.

init(Args) ->
	{ok, Args}.

handle_call(_Request, _From, State) ->
	{reply, ok, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

