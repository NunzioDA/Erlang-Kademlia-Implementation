% -----------------------------------------------------------------------------
% Module: utils
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-20
% Description: This module contains utility functions.
% -----------------------------------------------------------------------------

- module(utils).
- export([k_hash/2, get_subtree_index/2, xor_distance/2, sort_node_list/2, print_progress/1]).
- export([empty_branches/2, remove_duplicates/1, remove_contacted_nodes/2, print/1, print/2]).
- export([to_bit_list/1, print_routing_table/2, debug_print/1, debug_print/2, do_it_if_verbose/1]).
- export([verbose/0, set_verbose/1,most_significant_bit_index/1, most_significant_bit_index/2, branches_with_less_then/3]).


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
    ?MODULE:most_significant_bit_index(Xor).

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

% This function is used to sort a list of nodes by their xor distance from a target id.
sort_node_list(NodeList, TargetId) ->
    lists:sort(
        fun({Key1, _}, {Key2, _}) -> 
            ?MODULE:xor_distance(TargetId, Key1) < ?MODULE:xor_distance(TargetId, Key2) 
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

% 
empty_branches(RoutingTable, K) ->
    Tab2List = ets:tab2list(RoutingTable),
    length(Tab2List) =< K.

branches_with_less_then(RoutingTable, MinElems, K) ->
    Tab2List = ets:tab2list(RoutingTable),
    ControlList = lists:filter(
        fun({_, NodeList}) ->
           length(NodeList) < MinElems 
        end,
        Tab2List    
    ),
    length(ControlList) =< K.


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
    ?MODULE:do_it_if_verbose(fun() -> io:format(Format) end).
debug_print(Format, Data)->
    ?MODULE:do_it_if_verbose(fun() -> io:format(Format, Data) end).
% This function implements the verbosity check
do_it_if_verbose(Fun) ->
    Verbose = ?MODULE:verbose(),
    
    if Verbose ->
        Fun();
    true -> ok
    end.

% This function is used to print a progress bar
print_progress(ProgressRatio) ->
    Progress = round(ProgressRatio * 100),
    MaxLength = 30,
    CompletedLength = round(ProgressRatio * MaxLength),
    IncompleteLength = MaxLength - CompletedLength,
    Bar = "[" ++ lists:duplicate(CompletedLength, $=) 
              ++ lists:duplicate(IncompleteLength, $\s) 
              ++ "] " 
              ++ integer_to_list(Progress) ++ "%",
    io:format("\r~s  ", [Bar]),
    ok.