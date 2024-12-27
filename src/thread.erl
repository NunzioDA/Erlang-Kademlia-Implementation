-module(thread).

-export([ start/1]).

start(Function) ->
    ParentAddress = com:my_address(),
    Verbose = utils:verbose(),
    spawn(
        fun()->
            % Saving parent address and verbose in the new process
            % so it can behave like the parent
            utils:set_verbose(Verbose),
            com:save_address(ParentAddress),
            Function()
        end
    )
    % save_thread(Pid)
.

% save_thread(Pid)->
%     Threads = get_threads(),
%     put(my_threads, [Pid | Threads])
% .
    
% get_threads() ->
%     case get(my_threads) of
%         undefined -> [];
%         Threads -> Threads
%     end
% .

% set_verbose(Verbose) ->
%     Threads = get_threads(),
%     lists:foreach(
%         fun(X) ->
%             gen_server:cast(X, {verbose, Verbose})
%         end,
%         Threads
%     )
% .