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

-export([start/1, check_verbose/0, set_verbose/1]).

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

% This method has to be used in the function
% passed to the thread to check for verbosity changes
check_verbose() ->
    receive
        {verbose, Verbose} ->
            utils:set_verbose(Verbose)
    after 0 ->
        ok
    end
.

% This method is used to save the thread Pid in the 
% Parent process dictionary.
save_thread(Pid)->
    Threads = get_threads(),
    put(my_threads, [Pid | Threads])
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
    Threads = get_threads(),
    lists:foreach(
        fun(Pid) ->
            Pid ! {verbose, Verbose}
        end,
        Threads
    )
.