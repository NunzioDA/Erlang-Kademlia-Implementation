-module(thread).
-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3, start/1, set_verbose/1]).

start(Function) ->
    ParentAddress = com:my_address(),
    Verbose = utils:verbose(),
    Pid = spawn(
        fun()->
            % Saving parent address and verbose in the new process
            % so it can behave like the parent
            utils:set_verbose(Verbose),
            com:save_address(ParentAddress),
            Function()
        end
    ),
    save_thread(Pid)
.

save_thread(Pid)->
    Threads = get_threads(),
    put(my_threads, [Pid | Threads])
.
    
get_threads() ->
    case get(my_threads) of
        undefined -> [];
        Threads -> Threads
    end
.

set_verbose(Verbose) ->
    Threads = get_threads(),
    lists:foreach(
        fun(X) ->
            gen_server:cast(X, {verbose, Verbose})
        end,
        Threads
    )
.

init(Args) ->
	{ok, Args}.

handle_call(_, _, State) ->
	{reply, ok, State}.

handle_cast({verbose, Verbose}, State) ->
    utils:set_verbose(Verbose),
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.


