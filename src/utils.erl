% -----------------------------------------------------------------------------
% Module: utils
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-20
% Description: This module contains utility functions.
% -----------------------------------------------------------------------------

- module(utils).
- export([k_hash/2, get_subtree_index/2, xor_distance/2, sort_node_list/2, print_progress/2]).
- export([empty_branches/2, remove_duplicates/1, remove_contacted_nodes/2, print/1, print/2]).
- export([to_bit_list/1, print_routing_table/2, debug_print/1, debug_print/2, do_it_if_verbose/1]).
- export([verbose/0, set_verbose/1,most_significant_bit_index/1, most_significant_bit_index/2, pid_in_routing_table/3]).


% This function is used to convert a bitstring into a list of bits.
%%% Used for debugging purposes. %%%
to_bit_list(<<>>) -> 
    [];
to_bit_list(<<Bit:1/bits, Rest/bits>>) ->
    if Bit == <<1:1>> -> 
        NewBit = 1;
    true -> 
        NewBit = 0
    end,
    [NewBit] ++ ?MODULE:to_bit_list(Rest).


% This function is used to create a K-bit hash from a given data.
k_hash(Data, K) when is_pid(Data) ->
    k_hash(pid_to_list(Data), K);
k_hash(Data, K) when is_integer(K), K > 0 -> 
    Hash = crypto:hash(sha256, Data),
    % Takes the first K bits of the hash
    <<KBits:K/bits, _/bits>> = Hash,
    KBits.


% This function is used to get the index of the subtree that contains the target id.
get_subtree_index(Binary1, Binary2) ->
    Xor = ?MODULE:xor_distance(Binary1, Binary2),
    MostSignificant = ?MODULE:most_significant_bit_index(Xor),
    BitSize = bit_size(Binary1),
    if MostSignificant > BitSize ->
        BitSize;
    true ->
        MostSignificant
    end.

% This function is used to get the index of the most significant bit in a binary.
most_significant_bit_index(Binary) ->
    ?MODULE:most_significant_bit_index(Binary, 1).
% When the first bit is 1 or the binary is empty, the index is returned.
most_significant_bit_index(<<1:1, _/bits>>, Index) ->
    Index;
most_significant_bit_index(<<>>, Index) ->
    Index;
% Otherwise, the function is called recursively increasing the Index and removing the first bit.
most_significant_bit_index(<<_:1, Rest/bits>>, Index) ->
    ?MODULE:most_significant_bit_index(Rest, Index + 1).


% This function is used to calculate the xor distance between two binary ids.
xor_distance(HashID1, HashID2) ->
    K = bit_size(HashID1),
    <<N1:K>> = HashID1,
    <<N2:K>> = HashID2,
    R = N1 bxor N2,
    <<R:K>>.

% This function is used to sort a list of nodes by their XOR distance from a target ID.
% Using the PID along with the XOR distance to sort the node list makes the network more  
% reliable, even with a large number of collisions. This is particularly helpful when 
% the network has a large number of nodes and a small K parameter.
sort_node_list(NodeList, TargetId) ->
    lists:sort(
        fun({Key1, Pid1}, {Key2, Pid2}) -> 
            Distance1 = ?MODULE:xor_distance(TargetId, Key1),
            Distance2 = ?MODULE:xor_distance(TargetId, Key2),
            if Distance1 < Distance2 -> 
                true;
            true ->
                % If the distance is equal sort the 
                % list based on the Pid
                if Distance1 == Distance2 ->
                    Pid1 < Pid2;
                true ->
                    false
                end
            end
        end, 
        NodeList
    ).

% This function is used to remove duplicates from a list
remove_duplicates(List) ->
    lists:foldl(fun(Element, Acc) ->
        Condition = lists:member(Element, Acc),
        case Condition of
            true -> Acc; 
            false -> [Element | Acc]
        end
    end, [], List).

% This function is used to filter already contacted nodes
% from a nodes list
remove_contacted_nodes(NodesList, ContactedNodes) ->
    lists:foldl(fun(Element, Acc) ->
        {_,Pid} = Element,
        Condition = lists:member(Pid, ContactedNodes),
        case Condition of
            true -> Acc; 
            false -> [Element | Acc]
        end
    end, [], NodesList).

% This function is used to check if 
% there are empty branches in the routing table.
empty_branches(RoutingTable, K) ->

    AnyEmpty = lists:any(
        fun(Element) ->
            case ets:lookup(RoutingTable,Element) of
                [{_,[]}] -> true;
                [] -> true;
                _ ->
                    false
            end
        end,
        lists:seq(1,K)    
    ),

    AnyEmpty.

pid_in_routing_table(RoutingTable, Pid, K) ->
    BranchId = ?MODULE:get_subtree_index(?MODULE:k_hash(Pid, K), com:my_hash_id(K)),
    
    case ets:lookup(RoutingTable, BranchId) of
        [{_, NodeList}] ->
            lists:keymember(Pid, 2, NodeList);
        _ ->
            false
    end.

% Debugging function to print the routing table of the node.
print_routing_table(RoutingTable, MyHash) ->
    ets:tab2list(RoutingTable),
    lists:foldl(
        fun({BranchID, NodeList}, Acc) ->
            if BranchID < bit_size(MyHash) ->
                <<FirstBits:BranchID/bits, _/bits>> = MyHash;
            true ->
                FirstBits = MyHash
            end,
            Acc ++ [{?MODULE:to_bit_list(FirstBits), NodeList}]
        end,
        [],
        ets:tab2list(RoutingTable)
    ).

% Used to print console messages
print(Format)->
    io:format(Format).
print(Format, Data)->
    io:format(Format, Data).


% Verbose is used to decide if the debug_print function
% should print the text or not 
set_verbose(Verbose) ->
    put(verbose, Verbose).

% Used to get verbosity status
verbose() ->
    Result = get(verbose),
    if Result /= undefined ->
        Result;
    true ->
        false
    end.
% Used to print debugging messages
% It only pints when verbosity is set to true
debug_print(Format)->
    ?MODULE:do_it_if_verbose(fun() -> utils:print("[~p]",[com:my_address()]),io:format(Format) end).
debug_print(Format, Data)->
    ?MODULE:do_it_if_verbose(fun() -> utils:print("[~p]",[com:my_address()]),io:format(Format, Data) end).
% This function implements the verbosity check
do_it_if_verbose(Fun) ->
    Verbose = ?MODULE:verbose(),
    
    if Verbose ->
        Fun();
    true -> ok
    end.

% This function is used to print a progress bar
print_progress(ProgressRatio, PrintBar) ->
    Progress = round(ProgressRatio * 100),
    if PrintBar ->
        MaxLength = 30,
        CompletedLength = round(ProgressRatio * MaxLength),
        IncompleteLength = MaxLength - CompletedLength,
        Bar = "[" ++ lists:duplicate(CompletedLength, $=) 
                ++ lists:duplicate(IncompleteLength, $\s) 
                ++ "] ";
    true ->
        Bar = ""
    end,
    io:format("\r~s ~3B%  ", [Bar, Progress]).