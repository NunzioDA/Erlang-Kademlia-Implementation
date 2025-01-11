% -----------------------------------------------------------------------------
% Module: thread
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-27
% Description: This module manages the threads behaviour. A thread is considered
% every process that has been started from another process using the function
% thread:start, that is considered the thread parent. This makes the thread
% send messages using the parent address (Pid). 
% -----------------------------------------------------------------------------
% 

-module(thread).

-export([start/1, check_verbose/0, set_verbose/1, kill_all/0, save_thread/1, save_named/2]).
-export([get_threads/0, send_message_to_my_threads/1, kill/1, check_threads_status/0, get_named/1]).

start(Function) ->
    ParentAddress = com:my_address(),
    Verbose = utils:verbose(),
    Pid = spawn_link(
        fun()->
            % Saving parent address and verbose in the new process
            % so it can behave like the parent
            utils:set_verbose(Verbose),
            com:save_address(ParentAddress),
            Function()
        end
    ),
    ?MODULE:save_thread(Pid),
    Pid
.

% This method kills a thread
% where Thread is the Pid of 
% the thread to kill
kill(Thread) ->
    unlink(Thread),
    exit(Thread, kill).

% This method kills all the threads started from the parent process
kill_all()->
    Threads = ?MODULE:get_threads(),
    lists:foreach(
        fun(Thread) ->
            ?MODULE:kill(Thread)
        end,
        Threads
    )
.

% This method has to be used in the function
% passed to the thread to check for verbosity changes
check_verbose() ->
    receive
        {verbose, Verbose} ->
            % Discard any consecutive verbose messages and take only the last one
            LastVerbose = receiveLastVerbose(Verbose),
            utils:set_verbose(LastVerbose)
    after 0 ->
        ok
    end
.
% This function flushes every message except the last one
receiveLastVerbose(LastVerbose) ->
    receive
        {verbose, NewVerbose} ->
            receiveLastVerbose(NewVerbose)
    after 0 ->
        LastVerbose
    end
.

% This method is used to save the thread Pid in the 
% Parent process dictionary.
save_thread(Pid)->
    Threads = ?MODULE:get_threads(),
    put(my_threads, [Pid | Threads])
.

check_threads_status() ->
    Threads = ?MODULE:get_threads(),
    NewThreads = lists:foldl(
        fun(Pid, Acc) ->
            IsAlive = erlang:is_process_alive(Pid),
            if IsAlive ->
                [Pid | Acc];
            true -> 
                Acc
            end
        end,
        [],
        Threads
    ),
    put(my_threads, NewThreads)
.    
% This method is used to get all the threads started
% from a parent process 
get_threads() ->
    case get(my_threads) of
        undefined -> [];
        Threads -> Threads
    end
.

% This method is called from the parent process to
% automatically set the verbosity of all its threads 
set_verbose(Verbose) ->
    ?MODULE:send_message_to_my_threads({verbose, Verbose})
.
% This is a generic function that sends messages to
% the threads a process started.
% It also checks if threads are still alive, removing those
% who are not alive anymore.
send_message_to_my_threads(Message) -> 
    Threads = ?MODULE:get_threads(),
    NewThreads = lists:foldl(
        fun(Pid, Acc) ->
            IsAlive = erlang:is_process_alive(Pid),
            if IsAlive -> 
                Pid ! Message,
                [Pid | Acc];
            true -> 
                Acc
            end
        end,
        [],
        Threads
    ),
    put(my_threads, NewThreads),
    ok
.

% This function is used to save 
% a thread Pid with a name in the
% current process dictionary
save_named(Name, Pid) when is_pid(Pid) ->
    put(Name, Pid).

% This function is used to get 
% the pid of a thread saved with
% save_named eather in the curren
% process dictionary or in the parent
% process dictionary
get_named(Name) ->
    case get(Name) of
        undefined -> % It may be a subprocess of the node.
                     % Requiring node dictionary to get thread pid
            {_,Dictionary} = process_info(com:my_address(), dictionary),
            case lists:keyfind(Name, 1, Dictionary) of
                % The named thread is not started
                false -> undefined;
                % Returning the named thread pid
                {Name, ServerPidFound} -> ServerPidFound
            end;
        % Returning the named thread pid
        ServerPidFound -> ServerPidFound
    end.
