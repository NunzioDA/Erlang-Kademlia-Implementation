-module(com).
-export([save_address/1, my_address/0, send_request/2, send_async_request/2]).

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

% This function is used to send synchronous requests to a node.
% NodeId is the node to which the request is sent.
send_request(NodePid, Request) when is_list(NodePid) ->
    send_request(list_to_pid(NodePid), Request);
send_request(NodePid, Request) when is_pid(NodePid) ->
    
    try
        gen_server:call(NodePid, {Request, my_address()}, 5)
    catch _:Reason ->
        {error,Reason}
    end
.

% This function is used to send asynchronous requests to a node.
% NodeId is the node to which the request is sent.
send_async_request(NodePid, Request) ->

    gen_server:cast(NodePid, {Request, my_address()}).