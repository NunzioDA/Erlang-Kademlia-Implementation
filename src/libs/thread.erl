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

-export([start/1, check_verbose/0, set_verbose/1, kill_all/0, save_thread/1, save_named/2, receive_last_verbose/1]).
-export([get_threads/0, send_message_to_my_threads/1, kill/1, check_threads_status/0, get_named/1,thread_table_name/0]).
-export([create_threads_table/0, thread_table_exists/0, save_in_thread_table/2]).
-export([get_thread_table_ref/0, save_thread_table_ref/1, lookup_in_thread_table/1, update_my_thread_list/1]).
-export([named_thread_cast/1, init_thread/3]).


% This method is used to start a new thread. 
% The thread is started with the function passed as argument.
% The thread is linked to the parent process so that if the parent
% process dies, the thread dies too.
% The thread is saved in the parent thread table.
% The thread is started with the same verbosity and address
% of the parent process.
start(Function) ->
    % Saving the parent address, verbosity and 
    % thread table reference
    ParentAddress = com:my_address(),
    Verbose = utils:verbose(),
    ThreadTable = create_threads_table(),

    % Start the thread
    Pid = spawn_link(
        fun()->            
            ?MODULE:init_thread(ParentAddress, Verbose, ThreadTable),
            Function()
        end
    ),

    % Save the thread in the parent thread table
    ?MODULE:save_thread(Pid),
    Pid
.

% This method is used to initialize the thread
% with the verbosity and the address of the parent process
% The thread table reference is saved in the process dictionary
% as well so the thread can access the table
init_thread(ParentAddress, Verbose, ThreadTableRef) ->
    utils:set_verbose(Verbose),
    com:save_address(ParentAddress),
    ?MODULE:save_thread_table_ref(ThreadTableRef)
.
% This method kills a thread where Thread is the 
% Pid of the thread to kill
kill(Thread) ->
    unlink(Thread),
    exit(Thread, kill)
.

% This method kills all the threads started 
% from the parent process
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
            LastVerbose = ?MODULE:receive_last_verbose(Verbose),
            utils:set_verbose(LastVerbose)
    after 0 ->
        ok
    end
.

% This function flushes every message except the last one
receive_last_verbose(LastVerbose) ->
    receive
        {verbose, NewVerbose} ->
            ?MODULE:receive_last_verbose(NewVerbose)
    after 0 ->
        LastVerbose
    end
.

% This method is used to get the name of the thread table
thread_table_name() ->
    MyPid = com:my_address(),
    TableNameString = pid_to_list(MyPid) ++ "_threads",
    TableNameAtom = list_to_atom(TableNameString),
    TableNameAtom
.

% This method is used to create the thread table
% if it does not exist yet. The table is created as a set
% and is public so that every thread can access it.
% The reference to the table is saved in the process dictionary.
% If the table already exists, the reference is returned.
create_threads_table() ->
   case ?MODULE:thread_table_exists() of
        false -> 
            TableName = ?MODULE:thread_table_name(),
            Ref = ets:new(TableName, [set, public]),
            ?MODULE:save_thread_table_ref(Ref),
            Ref;
        true -> 
            ?MODULE:get_thread_table_ref()
    end
.

% This method is used to check if the thread table exists
% and if the reference is still valid.
thread_table_exists() ->
    case get_thread_table_ref() of
        undefined -> false;
        Ref -> 
            % Check if the reference is still valid
            ets:info(Ref) /= undefined
    end
.

% This method is used to save 
% the reference to the thread table
% in the process dictionary
save_thread_table_ref(Ref) ->
    put(thread_table, Ref)
.

% This method is used to get 
% the reference to the thread 
% table from the process dictionary       
get_thread_table_ref() ->
    get(thread_table)
.

% This method is used to save a 
% key-value pair in the thread table
save_in_thread_table(Key, Value) ->
    ThereadTable = ?MODULE:get_thread_table_ref(),
    ets:insert(ThereadTable, {Key, Value})
.

% This method is used to lookup a 
% key in the thread table
lookup_in_thread_table(Key) ->
    ThereadTable = ?MODULE:get_thread_table_ref(),
    case ets:lookup(ThereadTable, Key) of
        [] -> undefined;
        [{_, Value}] -> Value
    end
.


% This method is used to save the thread Pid in the 
% Parent process dictionary.
save_thread(Pid)->
    Threads = ?MODULE:get_threads(),
    ?MODULE:update_my_thread_list([Pid | Threads])
.

% This method is used to update the thread list
% in the parent process dictionary
update_my_thread_list(ThreadList) ->
    ?MODULE:save_in_thread_table('internal:my_threads', ThreadList) 
.

% This method is used to check if the threads 
% are still alive and remove the dead ones from the list
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
    ?MODULE:update_my_thread_list(NewThreads)
.  

% This method is used to get all the threads started
% from a parent process 
get_threads() ->
    case ?MODULE:lookup_in_thread_table('internal:my_threads') of
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
    ?MODULE:update_my_thread_list(NewThreads),
    ok
.

% This function is used to cast
% a generic name to an atom
named_thread_cast(Name) when is_atom(Name) -> 
    named_thread_cast(atom_to_list(Name))
;
named_thread_cast(Name) when is_list(Name) ->
    list_to_atom("external:" ++ Name)
.

% This function is used to save 
% a thread Pid with a name in the
% current process dictionary
save_named(Name, Pid) when is_pid(Pid) ->
    CastedName = ?MODULE:named_thread_cast(Name),
    ?MODULE:save_in_thread_table(CastedName, Pid)
.

% This function is used to get 
% the pid of a thread saved with
% save_named eather in the curren
% process dictionary or in the parent
% process dictionary
get_named(Name) ->
    CastedName = ?MODULE:named_thread_cast(Name),
    case ?MODULE:lookup_in_thread_table(CastedName) of
        undefined -> undefined;
        % Returning the named thread pid
        ServerPidFound -> ServerPidFound
    end
.