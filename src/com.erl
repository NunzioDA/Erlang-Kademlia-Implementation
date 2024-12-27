-module(com).
-export([save_address/1, my_address/0]).

% This function saves the node address (Pid) in the process 
% dictionary so that the process and all his subprocesses can
% use the same address
save_address(Address) ->
    put(my_address, Address).
% This function gets the process address
my_address() ->
    case get(my_address) of
        undefined -> self();
        Address->Address
    end.